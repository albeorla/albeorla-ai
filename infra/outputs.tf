output "site_bucket" {
  description = "GCS bucket holding the built site. CI deploys publish here."
  value       = google_storage_bucket.site.name
}

output "lb_ipv4" {
  description = "Global anycast IPv4 of the HTTPS load balancer."
  value       = google_compute_global_address.site_v4.address
}

output "lb_ipv6" {
  description = "Global anycast IPv6 of the HTTPS load balancer."
  value       = google_compute_global_address.site_v6.address
}

output "name_servers" {
  description = "Cloud DNS name servers. Set these at the Name.com registrar for albeorla.ai."
  value       = google_dns_managed_zone.site.name_servers
}

output "url_map_name" {
  description = "URL map name (used by CI for cache invalidation)."
  value       = google_compute_url_map.site.name
}

output "ssl_cert_name" {
  description = "Managed SSL cert name. Status reaches ACTIVE only after DNS cuts over."
  value       = google_compute_managed_ssl_certificate.site.name
}

output "deploy_service_account" {
  description = "Email of the GitHub Actions deploy SA. Set as repo secret GCP_DEPLOY_SA."
  value       = google_service_account.gh_deploy.email
}

output "wif_provider" {
  description = <<-EOT
    Full resource name of the GitHub OIDC provider. Set as repo secret
    GCP_WIF_PROVIDER. Empty until `github_repo` is set in terraform.tfvars.
  EOT
  value       = local.wif_enabled ? google_iam_workload_identity_pool_provider.github[0].name : ""
}
