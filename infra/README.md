# Infrastructure — albeorla.ai

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

- Registrar: **Name.com** (expires 2028-02-16).
- Active nameservers: `ns1.vercel-dns.com`, `ns2.vercel-dns.com`
  (i.e. the domain is currently pointed at Vercel DNS).

After `terraform apply` creates the Cloud DNS managed zone, you MUST log
into Name.com and replace those nameservers with the four values from
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
go active until the Name.com nameserver swap (above) has propagated.

## Post-apply checklist

1. Grab `terraform output name_servers`. Log into Name.com and set
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

## Destroy

```bash
terraform destroy
```

This will NOT delete the state bucket or the GCP project itself — those
were created out-of-band. Tear them down with `gcloud` if needed.
