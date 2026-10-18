# ---------------------------------------------------------------------------
# 1. Enable the GCP APIs that we need.
#    A new project has most APIs turned off; Terraform cannot create a
#    cluster until the Kubernetes Engine API is enabled.
# ---------------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",        # Kubernetes Engine API
    "compute.googleapis.com",          # Networking, load balancers, static IPs, Cloud NAT, TLS policy
    "storage.googleapis.com",          # Cloud Storage buckets for logs and traces
    "iam.googleapis.com",              # Service accounts
    "iamcredentials.googleapis.com",   # Needed by Workload Identity (pods acting as a service account)
    "cloudresourcemanager.googleapis.com", # Needed to grant IAM roles on the project
  ])

  project = var.project_id
  service = each.value

  # Do not switch the API off when we run "terraform destroy".
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# 2. Static global IP address for the Grafana load balancer.
#    We point the DNS record grafana.sheveria.com to this IP.
#    Because the IP is reserved, it stays the same even if the Ingress
#    is recreated, so DNS never has to change.
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "ingress_ip" {
  name       = "grafana-ingress-ip"
  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# 3. Service account for the cluster nodes (least privilege).
#    Without this, nodes run as the default Compute Engine account, which has
#    broad "Editor" rights on the whole project. If a pod were compromised,
#    an attacker could use those rights. This account may only do what a GKE
#    node needs (write logs/metrics, pull images).
# ---------------------------------------------------------------------------
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes"
  display_name = "GKE nodes (least privilege)"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "gke_nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount" # the minimal role designed for GKE nodes
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ---------------------------------------------------------------------------
# 4. GKE Standard cluster (control plane only).
#    The control plane is managed by Google. The worker nodes are defined
#    separately in the node pool below, so we decide how many nodes we have.
# ---------------------------------------------------------------------------
resource "google_container_cluster" "primary" {
  name = var.cluster_name

  # A region (not a zone) makes this a REGIONAL cluster: the control plane
  # and the nodes are spread over 3 zones, so one zone failure does not
  # take the cluster down.
  location = var.region

  # GKE requires a default node pool at creation time. We do not want it,
  # because we manage our own pool as a separate resource (see below).
  # So we create the smallest possible pool and delete it right away.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Settings for that temporary default pool. It exists only for a few
  # minutes, so we make it as cheap as possible: small standard disks
  # (they do not count against the SSD_TOTAL_GB quota, unlike the
  # 100 GB default disks that exceeded our quota).
  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 20
    disk_type       = "pd-standard"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Automatic upgrades follow the "REGULAR" channel: a good balance
  # between getting new versions and stability.
  release_channel {
    channel = "REGULAR"
  }

  # VPC-native networking: pods get their own IP ranges from the VPC.
  # An empty block lets GKE choose the ranges automatically.
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}

  # PRIVATE NODES: the nodes get only internal IP addresses and cannot be
  # reached from the internet. They reach the internet (to pull images, send
  # e-mail alerts) through Cloud NAT, see network.tf.
  # The Kubernetes API endpoint stays public (enable_private_endpoint = false)
  # and is protected by authentication, so kubectl works from any location.
  # Production hardening: add master_authorized_networks_config to allow the API
  # only from known addresses.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Workload Identity: lets pods use GCP permissions without storing
  # service account keys in the cluster. Used by Loki and Tempo (storage.tf).
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Set to true in a real production setup so the cluster cannot be deleted
  # by accident. It is false here so "terraform destroy" works for cleanup
  # after the test (this also saves money).
  deletion_protection = false

  # The temporary default node pool is deleted right after the cluster is created
  # (remove_default_node_pool above), so its settings (node_config) must never be
  # updated later. Without this rule, any change to node_config makes Terraform try
  # to update a pool that no longer exists and fail with
  # "Node pool default-pool not found on update".
  lifecycle {
    ignore_changes = [node_config]
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.gke_nodes,
    # Nodes need internet access (through NAT) as soon as they start.
    google_compute_router_nat.nat,
  ]
}

# ---------------------------------------------------------------------------
# 5. Node pool: the virtual machines that run our pods.
#    In a regional cluster, node_count is PER ZONE. With 3 zones and
#    node_count = 1 we get exactly 3 nodes (one in each zone).
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "primary_nodes" {
  name     = "main-pool"
  cluster  = google_container_cluster.primary.name
  location = var.region

  node_count = var.nodes_per_zone

  # Google keeps nodes healthy and up to date automatically.
  management {
    auto_repair  = true # recreate a node if it becomes unhealthy
    auto_upgrade = true # keep nodes on the cluster's Kubernetes version
  }

  node_config {
    machine_type = var.node_machine_type

    # Small, fast disks: saves cost and avoids hitting default disk quotas.
    disk_size_gb = 50
    disk_type    = "pd-balanced"

    # Run nodes as the dedicated least-privilege service account.
    service_account = google_service_account.gke_nodes.email

    # Broad API access scope; the real permissions are controlled by IAM
    # (the service account above), which is Google's recommended pattern.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required for Workload Identity to work on the nodes.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Protect against boot-level tampering: only signed boot software runs,
    # and the integrity of the node is monitored.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      env = "test"
    }
  }
}
