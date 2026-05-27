// Workload Identity Federation for GitHub Actions -> GCP.
//
// Lets the GitHub Actions deploy workflow impersonate a dedicated deploy
// service account without a long-lived JSON key. The provider is pinned to
// one specific GitHub repo and one branch via an attribute condition AND a
// principalSet binding -- both layers must match for impersonation to work.
//
// After `terraform apply`:
//   - Set repo secret GCP_WIF_PROVIDER to output `wif_provider`.
//   - Set repo secret GCP_DEPLOY_SA      to output `deploy_service_account`.
// See infra/README.md "GitHub Actions deploy" for the exact gh commands.

variable "github_repo" {
  description = <<-EOT
    GitHub repo allowed to deploy, in `owner/name` form (e.g.
    `albeorla/albeorla-ai`). Leave empty until the remote exists; an empty
    value disables the WIF resources so `terraform apply` stays safe.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.github_repo == "" || can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be `owner/name` (e.g. `albeorla/albeorla-ai`) or empty."
  }
}

variable "github_deploy_ref" {
  description = "Git ref allowed to deploy. Defaults to refs/heads/main."
  type        = string
  default     = "refs/heads/main"
}

locals {
  wif_enabled = var.github_repo != ""
}

// Dedicated deploy SA. No keys are created; impersonation only.
resource "google_service_account" "gh_deploy" {
  project      = var.project_id
  account_id   = "gh-actions-deploy"
  display_name = "GitHub Actions deploy (albeorla.ai)"
  description  = "Impersonated by GitHub Actions via Workload Identity Federation. No long-lived keys."

  depends_on = [google_project_service.enabled]
}

// Bucket-scoped object write. Project-wide storage roles are intentionally
// avoided. objectAdmin covers create/update/delete -- needed because the
// deploy uses `gcloud storage rsync ... --delete-unmatched-destination-objects`.
resource "google_storage_bucket_iam_member" "gh_deploy_bucket" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gh_deploy.email}"
}

// `gcloud storage rsync` to the bucket root calls `storage.buckets.get` for
// metadata, which objectAdmin does not include. legacyBucketReader adds only
// bucket-level GET/list -- no object or IAM permissions -- and is bucket-scoped.
resource "google_storage_bucket_iam_member" "gh_deploy_bucket_get" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.gh_deploy.email}"
}

// Custom role granting ONLY `compute.urlMaps.invalidateCache` at the project
// level. The predefined alternative (`roles/compute.loadBalancerAdmin`) is
// far broader -- it can mutate URL maps, backend services, certs, etc. The
// CDN invalidate call is a project-level operation, so the binding has to be
// project-level, but the permission set is a single verb.
resource "google_project_iam_custom_role" "cdn_invalidator" {
  project     = var.project_id
  role_id     = "cdnCacheInvalidator"
  title       = "CDN Cache Invalidator"
  description = "Minimum permission to invalidate Cloud CDN caches via URL map."
  permissions = ["compute.urlMaps.invalidateCache"]
  stage       = "GA"
}

resource "google_project_iam_member" "gh_deploy_invalidate" {
  project = var.project_id
  role    = google_project_iam_custom_role.cdn_invalidator.id
  member  = "serviceAccount:${google_service_account.gh_deploy.email}"
}

// Workload Identity Pool + GitHub OIDC provider. Gated on github_repo so
// `terraform apply` with the default empty value is a no-op for these
// resources -- the user can apply once the GitHub repo exists.
resource "google_iam_workload_identity_pool" "github" {
  count                     = local.wif_enabled ? 1 : 0
  project                   = var.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "OIDC federation pool for GitHub Actions deploys."

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count                              = local.wif_enabled ? 1 : 0
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"
  description                        = "GitHub Actions OIDC provider pinned to one repo + ref."

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  // Hard restriction: only tokens from the specific repo + ref pass. The
  // principalSet binding below adds a second layer pinned to the exact
  // `repo:<owner>/<name>:ref:<ref>` subject.
  attribute_condition = "assertion.repository == \"${var.github_repo}\" && assertion.ref == \"${var.github_deploy_ref}\""
}

// Allow only the specific repo+ref subject to impersonate the deploy SA.
resource "google_service_account_iam_member" "gh_deploy_wif" {
  count              = local.wif_enabled ? 1 : 0
  service_account_id = google_service_account.gh_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/subject/repo:${var.github_repo}:ref:${var.github_deploy_ref}"
}
