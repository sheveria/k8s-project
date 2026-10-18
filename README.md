# Kubernetes observability demo on GCP

A GKE cluster that runs a sample microservice application together with an
observability stack: **metrics, logs and traces** in one Grafana, published at
**https://grafana.sheveria.com**, with e-mail alerting. All infrastructure and
configuration is defined as code.

| Signal | Collected by | Stored in | Retention | Viewed in |
|---|---|---|---|---|
| Metrics | Prometheus (+ node-exporter, kube-state-metrics) | Prometheus (persistent disk) | 2 days | Grafana |
| Logs | Grafana Alloy | Loki, in a GCS bucket | 30 days | Grafana → Explore → Loki |
| Traces | OpenTelemetry (sent by the app) | Tempo, in a GCS bucket | 7 days | Grafana → Explore → Tempo |
| Alerts | Prometheus rules (default + custom) | Alertmanager | n/a | E-mail, Grafana → Alerting |

Documentation:

- [docs/architecture.md](docs/architecture.md): what is deployed, how it fits together, **why** each choice was made, the **bonus points** and the known limitations.
- [docs/operations.md](docs/operations.md): how to deploy, maintain, upgrade, troubleshoot, rebuild and tear down.

## Repository layout

```
.
├── terraform/            Infrastructure as code: private GKE cluster, Cloud NAT, buckets,
│                         service accounts, TLS policy, static IP, remote state
├── helm/
│   ├── observability/    Helm values (Prometheus/Grafana/Alertmanager, Loki, Tempo, Alloy),
│   │                     alert rules, the dashboard and the Grafana Ingress
│   └── app/              Manifest of the sample application (microsim)
├── scripts/deploy.ps1    Example: installs everything in one go (the steps are also listed in docs/operations.md)
└── docs/                 Documentation
```

## Quick start

Requirements: a GCP project with billing enabled, `gcloud`, `terraform`, `kubectl`, `helm`,
a DNS zone where you can create one A record, and an SMTP account (SMTP2GO) for alert e-mails.

1. Create the Terraform state bucket and the infrastructure (see [operations: first deployment](docs/operations.md#1-first-deployment)).
2. Fill in the e-mail settings, then install the stack with Helm and deploy the sample application.
3. Create the DNS record `grafana.<your-domain>` pointing to the reserved IP address.
4. Wait for the Google-managed certificate, then open Grafana.

## What this demo is, and is not

It is a deliberately small setup that is close to production in its
**security basics, data durability for logs and traces, alerting, reproducibility and structure**.
Prometheus (×2), Alertmanager (×3), Loki (×3) and Alloy (×2) are redundant; Tempo and Grafana are single replicas. The gaps and the path to production are listed in
[architecture: limitations and next steps](docs/architecture.md#limitations-and-next-steps),
and the optional extras that were attempted or described are in
[architecture: bonus points](docs/architecture.md#bonus-points).
