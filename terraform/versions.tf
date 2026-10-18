# Pin Terraform and provider versions so every run behaves the same way.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# The Google provider talks to the GCP API using your gcloud credentials
# (set up with: gcloud auth application-default login).
provider "google" {
  project = var.project_id
  region  = var.region
}
