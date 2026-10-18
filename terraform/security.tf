# ---------------------------------------------------------------------------
# TLS policy: which TLS versions and ciphers the public load balancer accepts.
# Old protocols (TLS 1.0 and 1.1) have known weaknesses, so we require 1.2+.
# The policy is attached to the Ingress in helm/observability/grafana-ingress.yaml
# (FrontendConfig).
# ---------------------------------------------------------------------------
resource "google_compute_ssl_policy" "grafana" {
  name            = "grafana-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"

  depends_on = [google_project_service.apis]
}
