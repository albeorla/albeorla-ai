# ------------------------------------------------------------------
# Cloud DNS managed zone for albeorla.ai.
#
# IMPORTANT: albeorla.ai is registered at Name.com and currently uses
# Vercel DNS (ns1.vercel-dns.com / ns2.vercel-dns.com). After this zone
# is created, you MUST update the nameservers at Name.com to the four
# values output by google_dns_managed_zone.site.name_servers, or the
# managed SSL cert and all DNS records below will never resolve.
# See infra/README.md.
# ------------------------------------------------------------------

resource "google_dns_managed_zone" "site" {
  name        = "albeorla-ai"
  dns_name    = "${var.domain}."
  description = "Public zone for albeorla.ai"
  project     = var.project_id
  labels      = var.labels

  dnssec_config {
    state = "on"
  }

  depends_on = [google_project_service.enabled]
}

# Apex A/AAAA -> LB
resource "google_dns_record_set" "apex_a" {
  name         = "${var.domain}."
  managed_zone = google_dns_managed_zone.site.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.site_v4.address]
  project      = var.project_id
}

resource "google_dns_record_set" "apex_aaaa" {
  name         = "${var.domain}."
  managed_zone = google_dns_managed_zone.site.name
  type         = "AAAA"
  ttl          = 300
  rrdatas      = [google_compute_global_address.site_v6.address]
  project      = var.project_id
}

# www -> LB (cert covers both names, so the LB serves www directly)
resource "google_dns_record_set" "www_a" {
  name         = "${var.www_domain}."
  managed_zone = google_dns_managed_zone.site.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.site_v4.address]
  project      = var.project_id
}

resource "google_dns_record_set" "www_aaaa" {
  name         = "${var.www_domain}."
  managed_zone = google_dns_managed_zone.site.name
  type         = "AAAA"
  ttl          = 300
  rrdatas      = [google_compute_global_address.site_v6.address]
  project      = var.project_id
}

# CAA so only Google can issue certs for this domain (defense in depth).
resource "google_dns_record_set" "caa" {
  name         = "${var.domain}."
  managed_zone = google_dns_managed_zone.site.name
  type         = "CAA"
  ttl          = 3600
  rrdatas      = ["0 issue \"pki.goog\""]
  project      = var.project_id
}
