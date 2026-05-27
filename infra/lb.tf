# ------------------------------------------------------------------
# Global external HTTPS load balancer fronting the GCS bucket via CDN
# ------------------------------------------------------------------

# Reserved global anycast IPv4 + IPv6
resource "google_compute_global_address" "site_v4" {
  name       = "albeorla-ai-ipv4"
  ip_version = "IPV4"
  project    = var.project_id
  depends_on = [google_project_service.enabled]
}

resource "google_compute_global_address" "site_v6" {
  name       = "albeorla-ai-ipv6"
  ip_version = "IPV6"
  project    = var.project_id
  depends_on = [google_project_service.enabled]
}

# Backend bucket with CDN enabled
resource "google_compute_backend_bucket" "site" {
  name        = "albeorla-ai-backend"
  description = "Static site backend bucket for albeorla.ai"
  bucket_name = google_storage_bucket.site.name
  enable_cdn  = true
  project     = var.project_id

  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    client_ttl                   = 3600
    default_ttl                  = 3600
    max_ttl                      = 86400
    negative_caching             = true
    serve_while_stale            = 86400
    request_coalescing           = true
    signed_url_cache_max_age_sec = 0
  }
}

# Google-managed SSL certificate covering apex + www
resource "google_compute_managed_ssl_certificate" "site" {
  name    = "albeorla-ai-cert"
  project = var.project_id

  managed {
    domains = [var.domain, var.www_domain]
  }
}

# URL map (HTTPS) — sends everything to the backend bucket
resource "google_compute_url_map" "site" {
  name            = "albeorla-ai-urlmap"
  default_service = google_compute_backend_bucket.site.id
  project         = var.project_id
}

# URL map (HTTP) — 301 redirect everything to HTTPS
resource "google_compute_url_map" "http_redirect" {
  name    = "albeorla-ai-http-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# HTTPS target proxy
resource "google_compute_target_https_proxy" "site" {
  name             = "albeorla-ai-https-proxy"
  url_map          = google_compute_url_map.site.id
  ssl_certificates = [google_compute_managed_ssl_certificate.site.id]
  project          = var.project_id
}

# HTTP target proxy (for redirect)
resource "google_compute_target_http_proxy" "redirect" {
  name    = "albeorla-ai-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
  project = var.project_id
}

# Forwarding rules: 443 IPv4, 443 IPv6, 80 IPv4, 80 IPv6
resource "google_compute_global_forwarding_rule" "https_v4" {
  name                  = "albeorla-ai-https-v4"
  ip_address            = google_compute_global_address.site_v4.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.site.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  project               = var.project_id
}

resource "google_compute_global_forwarding_rule" "https_v6" {
  name                  = "albeorla-ai-https-v6"
  ip_address            = google_compute_global_address.site_v6.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.site.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  project               = var.project_id
}

resource "google_compute_global_forwarding_rule" "http_v4" {
  name                  = "albeorla-ai-http-v4"
  ip_address            = google_compute_global_address.site_v4.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  project               = var.project_id
}

resource "google_compute_global_forwarding_rule" "http_v6" {
  name                  = "albeorla-ai-http-v6"
  ip_address            = google_compute_global_address.site_v6.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  project               = var.project_id
}
