variable "project_id" {
  description = "GCP project ID where everything is created."
  type        = string
  default     = "k8s-for-test-512006"
}

variable "region" {
  description = "GCP region for the cluster. A region means a regional cluster (spread across zones)."
  type        = string
  default     = "europe-west1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "obs-demo"
}

variable "nodes_per_zone" {
  description = "Number of nodes in EACH zone. The region has 3 zones, so 1 gives 3 nodes in total."
  type        = number
  default     = 1
}

variable "node_machine_type" {
  description = "VM type for the nodes. e2-standard-4 = 4 vCPU and 16 GB RAM per node. Sized so that all pods still fit on 2 nodes if one node fails."
  type        = string
  default     = "e2-standard-4"
}

variable "master_ipv4_cidr_block" {
  description = "Private /28 range used by the Google-managed control plane. Must not overlap with any other range in the VPC."
  type        = string
  default     = "172.16.0.0/28"
}
