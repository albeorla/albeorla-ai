# Infrastructure — albeorla.ai

## Current state (2026-05-27)

Bootstrap and first `terraform apply` are complete. The site stack is
live on GCP but cannot serve traffic until the registrar nameserver
swap at Vercel (domain management UI) is done.

- GCP project: `albeorla-ai-site` — applied ✓
- Billing account `012A77-3EB40A-DD7869` linked — applied ✓
- APIs enabled (cloudresourcemanager, iam, serviceusage, storage,
  compute, dns, certificatemanager) — applied ✓
- Terraform state bucket `gs://albeorla-ai-tfstate` (us-central1,
  uniform access, versioning on) — applied ✓
- Terraform: 26 resources created (GCS site bucket, global LB v4/v6,
  Cloud CDN, HTTP->HTTPS redirect, managed SSL cert, Cloud DNS zone,
  A/AAAA/CAA records).
- LB IPv4: `8.233.161.192`
- LB IPv6: `2600:1901:0:c7e7::`
- Managed SSL cert: `albeorla-ai-cert` — `PROVISIONING` (expected; will
  stay pending until the NS swap below propagates).

### Name servers to set at Vercel (domain management UI)

Replace the current Vercel nameservers on `albeorla.ai` with these four
Google Cloud DNS nameservers:

```
ns-cloud-b1.googledomains.com.
ns-cloud-b2.googledomains.com.
ns-cloud-b3.googledomains.com.
ns-cloud-b4.googledomains.com.
```

### Post-NS-swap verification

After saving the NS change at Vercel (domain management UI), run these to confirm:

```bash
# 1. Confirm public DNS is now pointing at Google's nameservers.
dig +short NS albeorla.ai

# 2. Confirm apex/www resolve to the LB addresses.
dig +short A albeorla.ai
dig +short AAAA albeorla.ai
dig +short A www.albeorla.ai

# 3. Watch the managed cert flip PROVISIONING -> ACTIVE
#    (usually 15-60 min after DNS propagates, can take a few hours).
gcloud compute ssl-certificates describe albeorla-ai-cert \
  --global --project=albeorla-ai-site \
  --format="value(managed.status,managed.domainStatus)"

# 4. List all certs for the project (sanity check).
gcloud compute ssl-certificates list --project=albeorla-ai-site
```

When the cert reports `ACTIVE` the site will serve over HTTPS.

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

## Heads-up on the registrar (READ THIS FIRST)

The brief assumed the domain was in Google Domains / Cloud DNS. It is
not. As of 2026-05-27:

- Domain managed via **Vercel** (Vercel resells through Name.com under
  the hood, but the user-facing surface for DNS / NS changes is the
  Vercel dashboard at vercel.com/<team>/domains).
- Active nameservers: `ns1.vercel-dns.com`, `ns2.vercel-dns.com`
  (i.e. the domain is currently pointed at Vercel DNS).

After `terraform apply` creates the Cloud DNS managed zone, you MUST go
into Vercel's domain settings for `albeorla.ai` and replace those
nameservers with the four values from
the `name_servers` Terraform output. Until you do, the managed SSL cert
will sit in `PROVISIONING` forever and the site won't serve.

If the apex is presently serving anything via Vercel that you want to
keep alive, do the cutover during a quiet window — DNS propagation can
take 24-48h worst case.

## One-time bootstrap (before first `terraform init`)

These steps create the GCP project, attach billing, and create the
state bucket. Run them manually — Terraform itself stores state in the
bucket, so it can't create it.

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

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # edit if needed
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Expected first-apply duration: 15-25 minutes, dominated by the managed
SSL certificate going through `PROVISIONING -> ACTIVE`. The cert won't
go active until the Vercel (domain management UI) nameserver swap (above) has propagated.

## Post-apply checklist

1. Grab `terraform output name_servers`. Log into Vercel (domain management UI) and set
   those four NS records on `albeorla.ai`. Save.
2. Wait for `dig +short NS albeorla.ai` to return the Google NS values
   (usually 5-60 min, up to 48h).
3. Watch the cert:
   ```bash
   gcloud compute ssl-certificates describe albeorla-ai-cert \
     --global --project=albeorla-ai-site \
     --format="value(managed.status,managed.domainStatus)"
   ```
   When it flips to `ACTIVE`, the site serves.
4. Configure the GitHub Actions deploy workflow (see
   `.github/workflows/deploy.yml`) with:
   - A Workload Identity Federation provider, OR a service account
     key stored as `GCP_SA_KEY` (less ideal).
   - The bucket name and URL map name from outputs.

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

### One-time setup after creating the GitHub repo

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

After the secrets are in place and the SSL cert is `ACTIVE`:

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
