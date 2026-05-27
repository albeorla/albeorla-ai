locals {
  required_services = [
    "compute.googleapis.com",
    "dns.googleapis.com",
    "storage.googleapis.com",
    "certificatemanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each                   = toset(local.required_services)
  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}
