# Installs the observability stack and the sample application into the
# cluster that kubectl currently points to.
# Run from anywhere:  .\scripts\deploy.ps1
# Prerequisite: run "terraform apply" first. Terraform creates the cluster, the
# reserved IP address, the GCS buckets, Cloud NAT, and the SSL policy.
# It is safe to run the script again: "helm upgrade --install" updates what exists.

# Native commands (helm, kubectl) do not stop PowerShell on errors by
# themselves, so every step is followed by an explicit exit code check.
$ErrorActionPreference = "Continue"

function Assert-Ok {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) { throw "Step failed: $Step (exit code $LASTEXITCODE)" }
}

# Repository root = the parent of the folder this script lives in.
$root = Split-Path -Parent $PSScriptRoot
$obs  = Join-Path $root "helm\observability"
$app  = Join-Path $root "helm\app"

# Chart versions are pinned, so every deployment gives the same result.
$kpsVersion   = "92.10.1"
$lokiVersion  = "18.17.1"
$tempoVersion = "3.2.0"
$alloyVersion = "1.13.1"

# Stop early if the e-mail settings were not filled in.
if (Select-String -Path (Join-Path $obs "kube-prometheus-stack-values.yaml") -Pattern "CHANGE_ME" -Quiet) {
    throw "Replace CHANGE_ME_SMTP2GO_USER in kube-prometheus-stack-values.yaml with your SMTP2GO user name first."
}

Write-Host "==> Adding Helm repositories"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
Assert-Ok "helm repo update"

Write-Host "==> Creating namespace 'monitoring'"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
Assert-Ok "create namespace"

# The Grafana admin password lives only in the cluster, never in git.
Write-Host "==> Checking Grafana admin secret"
$existing = kubectl get secret grafana-admin -n monitoring --ignore-not-found -o name
if (-not $existing) {
    $password = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    kubectl create secret generic grafana-admin -n monitoring `
        --from-literal=admin-user=admin `
        --from-literal=admin-password=$password
    Assert-Ok "create grafana-admin secret"
    Write-Host "    Secret created. See docs for how to read the password."
} else {
    Write-Host "    Secret already exists, keeping it."
}

# The SMTP password used by Alertmanager for e-mail alerts (also only in the cluster).
Write-Host "==> Checking Alertmanager SMTP secret"
$smtpExisting = kubectl get secret alertmanager-smtp -n monitoring --ignore-not-found -o name
if (-not $smtpExisting) {
    $secure = Read-Host "SMTP2GO password of the SMTP user" -AsSecureString
    $smtpPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    kubectl create secret generic alertmanager-smtp -n monitoring --from-literal=password=$smtpPassword
    Assert-Ok "create alertmanager-smtp secret"
} else {
    Write-Host "    Secret already exists, keeping it."
}

# Order matters: the first chart installs the Prometheus CRDs that Tempo's
# ServiceMonitor needs, and Loki/Tempo must exist before Alloy and microsim send data to them.
Write-Host "==> Installing kube-prometheus-stack (Prometheus + Grafana)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --namespace monitoring --version $kpsVersion `
    -f (Join-Path $obs "kube-prometheus-stack-values.yaml") --wait --timeout 10m
Assert-Ok "kube-prometheus-stack"

Write-Host "==> Installing Loki (logs)"
helm upgrade --install loki grafana-community/loki `
    --namespace monitoring --version $lokiVersion `
    -f (Join-Path $obs "loki-values.yaml") --wait --timeout 10m
Assert-Ok "loki"

Write-Host "==> Installing Tempo (traces)"
helm upgrade --install tempo grafana-community/tempo `
    --namespace monitoring --version $tempoVersion `
    -f (Join-Path $obs "tempo-values.yaml") --wait --timeout 10m
Assert-Ok "tempo"

Write-Host "==> Installing Alloy (log collector)"
helm upgrade --install alloy grafana/alloy `
    --namespace monitoring --version $alloyVersion `
    -f (Join-Path $obs "alloy-values.yaml") --wait --timeout 10m
Assert-Ok "alloy"

Write-Host "==> Applying custom alert rules and the dashboard"
kubectl apply -f (Join-Path $obs "custom-alerts.yaml")
Assert-Ok "custom alerts"
kubectl apply -f (Join-Path $obs "dashboard-app-overview.yaml")
Assert-Ok "dashboard"

Write-Host "==> Deploying the sample application (microsim)"
kubectl apply -f (Join-Path $app "microsim.yaml")
Assert-Ok "microsim"

Write-Host "==> Publishing Grafana (Ingress + certificate)"
kubectl apply -f (Join-Path $obs "grafana-ingress.yaml")
Assert-Ok "grafana ingress"

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  1. Create the DNS A record grafana.sheveria.com -> (terraform output ingress_ip)"
Write-Host "  2. Wait 15-60 minutes for the certificate:  kubectl get managedcertificate -n monitoring"
Write-Host "  3. Open https://grafana.sheveria.com (user: admin)"
