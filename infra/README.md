# Infrastructure — albeorla.ai

## Current state (verified 2026-07-29)

Everything below is applied and serving. `https://albeorla.ai` returns
200 over HTTPS, and GitHub Actions has been deploying to the bucket on
every push to `main` since 2026-05-27.

- GCP project: `albeorla-ai-site` - applied
- Billing account `012A77-3EB40A-DD7869` linked - applied
- APIs enabled (cloudresourcemanager, iam, serviceusage, storage,
  compute, dns, certificatemanager) - applied
- Terraform state bucket `gs://albeorla-ai-tfstate` (us-central1,
  uniform access, versioning on) - applied
- Terraform: GCS site bucket, global LB v4/v6, Cloud CDN, HTTP->HTTPS
  redirect, managed SSL cert, Cloud DNS zone, A/AAAA/CAA records, plus
  the WIF resources in `wif.tf`.
- LB IPv4: `8.233.161.192`
- LB IPv6: `2600:1901:0:c7e7::`
- Managed SSL cert: `albeorla-ai-cert` - `ACTIVE`
- Nameservers: cut over from Vercel to Google Cloud DNS
  (`ns-cloud-b1..b4.googledomains.com.`) - done
- Repo secrets `GCP_WIF_PROVIDER` and `GCP_DEPLOY_SA` - set

### Verification commands

To re-confirm any of the above:

```bash
# 1. Confirm public DNS is now pointing at Google's nameservers.
dig +short NS albeorla.ai

# 2. Confirm apex/www resolve to the LB addresses.
dig +short A albeorla.ai
dig +short AAAA albeorla.ai
dig +short A www.albeorla.ai

# 3. Check the managed cert (should report ACTIVE).
gcloud compute ssl-certificates describe albeorla-ai-cert \
  --global --project=albeorla-ai-site \
  --format="value(managed.status,managed.domainStatus)"

# 4. List all certs for the project (sanity check).
gcloud compute ssl-certificates list --project=albeorla-ai-site
```

---

Terraform configuration that provisions a static-site stack on GCP for
`albeorla.ai`:

- A single GCS bucket holding the built Astro site (uniform bucket-level
  access, public object read).
- A global HTTPS load balancer with a Google-managed SSL certificate
  covering apex + `www`.
- Cloud CDN in front of the bucket.
- HTTP -> HTTPS 301 redirect.
- Cloud DNS managed zone with A/AAAA for apex and `www`, plus a CAA
  record pinning issuance to Google.
- IPv4 and IPv6 anycast addresses.

State lives in a GCS bucket (`albeorla-ai-tfstate`) with versioning
enabled. The state bucket is bootstrapped out-of-band — see below.

## Registrar history (done, kept for context)

The original brief assumed the domain lived in Google Domains / Cloud
DNS. It did not. The domain is registered through **Vercel** (which
resells via Name.com under the hood), and the user-facing surface for
DNS and nameserver changes is the Vercel dashboard at
vercel.com/<team>/domains.

The nameservers were pointed at `ns1.vercel-dns.com` /
`ns2.vercel-dns.com`. On 2026-05-27 they were replaced with the four
Cloud DNS values from the `name_servers` Terraform output, which is what
let the managed SSL cert reach `ACTIVE`.

Practical consequence today: DNS records for `albeorla.ai` are managed
by Terraform in `dns.tf`, not in the Vercel dashboard. Adding a record
there will do nothing. The one thing still owned by Vercel is the
registration and the nameserver delegation itself, so do not let the
domain's NS settings get reset there.

## One-time bootstrap (completed 2026-05-27, kept for rebuilds)

These steps create the GCP project, attach billing, and create the
state bucket. Run them manually - Terraform itself stores state in the
bucket, so it can't create it. They have already been run for
`albeorla-ai-site`; you only need them to stand the stack up somewhere
new.

```bash
# 1. Create the project (skip if it already exists).
gcloud projects create albeorla-ai-site \
  --name="albeorla.ai site" \
  --set-as-default

# 2. Attach billing.
gcloud beta billing projects link albeorla-ai-site \
  --billing-account=012A77-3EB40A-DD7869

# 3. Enable the APIs Terraform itself needs to call.
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  --project=albeorla-ai-site

# 4. Create the tfstate bucket with versioning.
gcloud storage buckets create gs://albeorla-ai-tfstate \
  --project=albeorla-ai-site \
  --location=us-central1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://albeorla-ai-tfstate --versioning

# 5. Set local ADC for Terraform.
gcloud auth application-default login
```

## Apply

`infra/terraform.tfvars` is gitignored, so a fresh checkout needs it
recreated from the example (project id, billing account, region, domain,
www domain, and `github_repo = "albeorla/albeorla-ai"`).

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # only on a fresh checkout
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Routine applies are fast. The 15-25 minute first apply was dominated by
the managed SSL certificate going through `PROVISIONING -> ACTIVE`, which
completed once the nameserver cutover propagated. If the cert ever goes
back to `PROVISIONING`, check the nameserver delegation first.

## Post-apply checklist (completed 2026-05-27, redo only after a destroy)

1. Grab `terraform output name_servers`. Log into Vercel (domain
   management UI) and set those four NS records on `albeorla.ai`. Save.
2. Wait for `dig +short NS albeorla.ai` to return the Google NS values
   (usually 5-60 min, up to 48h).
3. Watch the cert:
   ```bash
   gcloud compute ssl-certificates describe albeorla-ai-cert \
     --global --project=albeorla-ai-site \
     --format="value(managed.status,managed.domainStatus)"
   ```
   When it flips to `ACTIVE`, the site serves.
4. Set the deploy workflow secrets from the Terraform outputs (see the
   Workload Identity Federation steps below). The deploy workflow reads
   the bucket name and URL map name from its own `env:` block, so those
   must match `terraform output site_bucket` and
   `terraform output url_map_name`.

## GitHub Actions deploy

The Astro build + GCS sync + CDN invalidate runs in
`.github/workflows/deploy.yml`. It authenticates via Workload Identity
Federation (no long-lived service account keys). The GCP side is
defined in `infra/wif.tf` and is gated on the `github_repo` Terraform
variable -- the WIF resources are only created once you've picked a
GitHub repo URL.

### IAM granted to the deploy SA (`gh-actions-deploy@...`)

- `roles/storage.objectAdmin` -- **scoped to the site bucket only**.
  Needed because the workflow uses `gcloud storage rsync --delete-
  unmatched-destination-objects`. Not granted at the project level.
- Custom role `cdnCacheInvalidator` with the single permission
  `compute.urlMaps.invalidateCache` -- granted at the project level
  because the invalidate call is project-scoped, but the permission
  set is one verb. (The predefined alternative
  `roles/compute.loadBalancerAdmin` would let the SA mutate URL maps,
  backend services, and SSL certs -- way too broad.)
- `roles/iam.workloadIdentityUser` on the SA itself, bound to the
  exact subject `repo:<owner>/<name>:ref:refs/heads/main`.

The OIDC provider also has an `attribute_condition` pinning
`assertion.repository` and `assertion.ref` to the same values -- a
second layer of restriction on top of the principalSet binding.

### Wiring the deploy secrets (done; repeat only to rotate or re-bootstrap)

The repo is `albeorla/albeorla-ai`, `github_repo` is already set in
`terraform.tfvars`, and both secrets exist. These are the steps that
produced them.

```bash
cd infra

# 1. Set the repo identifier and apply. `github_deploy_ref` defaults to
#    refs/heads/main; override only if you need a different branch.
cat >> terraform.tfvars <<'EOF'
github_repo = "albeorla/albeorla-ai"   # <-- your actual owner/name
EOF

terraform plan -out=tfplan
terraform apply tfplan

# 2. Grab the two outputs.
WIF_PROVIDER=$(terraform output -raw wif_provider)
DEPLOY_SA=$(terraform output -raw deploy_service_account)

# 3. Set them as repo secrets via gh CLI (from the repo root).
cd ..
gh secret set GCP_WIF_PROVIDER --body "$WIF_PROVIDER"
gh secret set GCP_DEPLOY_SA    --body "$DEPLOY_SA"

# 4. Verify the secrets exist (values are write-only via API).
gh secret list
```

### Testing the deploy

```bash
# Trigger the workflow manually without pushing.
gh workflow run deploy.yml

# Watch it.
gh run watch
```

Or push a no-op commit to `main` and let the `on: push` trigger fire.
If auth fails, the most common causes are: (1) `id-token: write` not
in the job permissions (it is, in this workflow), (2) the repo
identifier in `github_repo` doesn't match the actual repo, or (3) the
deploy is running on a branch other than `refs/heads/main`.

## Destroy

```bash
terraform destroy
```

This will NOT delete the state bucket or the GCP project itself — those
were created out-of-band. Tear them down with `gcloud` if needed.
