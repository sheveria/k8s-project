# ---------------------------------------------------------------------------
# Cloud NAT: outbound internet access for the PRIVATE nodes.
#
# Private nodes have no public IP, so by themselves they cannot reach the
# internet. Cloud NAT lets them start connections to the outside (pull
# container images, send e-mail alerts) while nothing from the internet can
# start a connection to them.
# ---------------------------------------------------------------------------
resource "google_compute_router" "nat" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = "default" # the cluster uses the project's default network

  depends_on = [google_project_service.apis]
}

resource "google_compute_router_nat" "nat" {
  name   = "${var.cluster_name}-nat"
  router = google_compute_router.nat.name
  region = var.region

  # Google allocates and manages the outbound IP addresses.
  nat_ip_allocate_option = "AUTO_ONLY"

  # Apply NAT to node, pod and service ranges of every subnet.
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Log only errors (for example, when NAT ports run out).
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
