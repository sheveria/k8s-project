# ---------------------------------------------------------------------------
# Object storage (GCS buckets) for logs (Loki) and traces (Tempo).
#
# Why: a pod disk is tied to one zone and one pod, and it is small and
# relatively expensive. A GCS bucket survives the loss of a pod, a node or a
# whole zone, grows without limit and is much cheaper per GB. This is what
# makes long-term log retention practical.
#
# For each component we create:
#   1. a bucket for its data,
#   2. a Google service account (GSA) that is allowed to use ONLY that bucket,
#   3. a Workload Identity binding that lets one specific Kubernetes service
#      account (KSA) act as that GSA. No keys or passwords are stored anywhere.
# ---------------------------------------------------------------------------
locals {
  storage_components = {
    loki = {
      ksa_namespace  = "monitoring"
      ksa_name       = "loki" # must match serviceAccount.name in loki-values.yaml
      lifecycle_days = 45     # safety net only: Loki deletes data itself after 30 days
    }
    tempo = {
      ksa_namespace  = "monitoring"
      ksa_name       = "tempo" # must match serviceAccount.name in tempo-values.yaml
      lifecycle_days = 14      # safety net only: Tempo deletes data itself after 7 days
    }
  }
}

# 1. One bucket per component.
resource "google_storage_bucket" "obs" {
  for_each = local.storage_components

  name     = "${var.project_id}-${each.key}"
  location = var.region

  # Access is controlled only by IAM, and the bucket can never be made public.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Allows "terraform destroy" to delete a bucket that still contains data.
  # Set to false in a real production setup.
  force_destroy = true

  # Safety net: delete anything older than N days, even if the application
  # failed to clean it up. The application's own retention is shorter.
  lifecycle_rule {
    condition {
      age = each.value.lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}

# 2. One Google service account per component.
resource "google_service_account" "obs" {
  for_each = local.storage_components

  account_id   = "${each.key}-gcs"
  display_name = "${each.key} access to its GCS bucket"

  depends_on = [google_project_service.apis]
}

# Least privilege: each account can manage objects in its OWN bucket only.
resource "google_storage_bucket_iam_member" "obs" {
  for_each = local.storage_components

  bucket = google_storage_bucket.obs[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.obs[each.key].email}"
}

# Reading the bucket's own metadata (storage.buckets.get) is a separate permission
# that "objectAdmin" does not include. Tempo checks the bucket with this call when it
# starts and fails with a 403 error without it. The legacy bucket reader role adds
# exactly that (plus listing objects) and nothing that could change the bucket.
resource "google_storage_bucket_iam_member" "obs_bucket_reader" {
  for_each = local.storage_components

  bucket = google_storage_bucket.obs[each.key].name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.obs[each.key].email}"
}

# 3. Workload Identity: allow the Kubernetes service account to act as the
#    Google service account. The member format is:
#    serviceAccount:<project>.svc.id.goog[<namespace>/<ksa-name>]
resource "google_service_account_iam_member" "workload_identity" {
  for_each = local.storage_components

  service_account_id = google_service_account.obs[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.ksa_namespace}/${each.value.ksa_name}]"

  # The identity pool "<project>.svc.id.goog" is created together with the cluster.
  depends_on = [google_container_cluster.primary]
}
