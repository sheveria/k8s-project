output "cluster_name" {
  description = "Name of the created GKE cluster."
  value       = google_container_cluster.primary.name
}

output "get_credentials_command" {
  description = "Run this command to let kubectl and helm talk to the cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "ingress_ip" {
  description = "Create a DNS A record grafana.sheveria.com pointing to this IP."
  value       = google_compute_global_address.ingress_ip.address
}

output "storage_buckets" {
  description = "GCS buckets used by Loki and Tempo."
  value       = { for name, bucket in google_storage_bucket.obs : name => bucket.name }
}

output "storage_service_accounts" {
  description = "Google service accounts that Loki and Tempo use (referenced in their Helm values)."
  value       = { for name, sa in google_service_account.obs : name => sa.email }
}

output "node_service_account" {
  description = "Least-privilege service account the cluster nodes run as."
  value       = google_service_account.gke_nodes.email
}
