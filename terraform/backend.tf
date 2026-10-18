# Remote state: Terraform keeps a record of what it created in this bucket
# instead of on your laptop. This allows teamwork and protects against
# losing the state file.
#
# The bucket must exist BEFORE "terraform init" (see docs: bootstrap step).
# Backend blocks cannot use variables, so the values are hardcoded here.
terraform {
  backend "gcs" {
    bucket = "k8s-for-test-512006-tfstate"
    prefix = "infra"
  }
}
