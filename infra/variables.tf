variable "project_id" {
  description = "GCP project ID hosting the albeorla.ai site. Create out-of-band; see infra/README.md."
  type        = string
  default     = "albeorla-ai-site"
}

variable "billing_account" {
  description = "GCP billing account ID. Required only when bootstrapping the project."
  type        = string
  default     = ""
}

variable "region" {
  description = "Default region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "domain" {
  description = "Apex domain served by the site."
  type        = string
  default     = "albeorla.ai"
}

variable "www_domain" {
  description = "WWW subdomain. Will redirect (or alias) to apex."
  type        = string
  default     = "www.albeorla.ai"
}

variable "site_bucket_name" {
  description = "GCS bucket holding the built static site. Must be globally unique."
  type        = string
  default     = "albeorla-ai-site"
}

variable "labels" {
  description = "Default resource labels."
  type        = map(string)
  default = {
    project = "albeorla-ai"
    managed = "terraform"
  }
}
