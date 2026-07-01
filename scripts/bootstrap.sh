#!/usr/bin/env bash
# Bootstrap the local cluster: install ArgoCD and apply the root App of Apps
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Adding ArgoCD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values "${REPO_ROOT}/bootstrap/argocd/values.yaml" \
  --wait

echo "==> Waiting for ArgoCD to be ready..."
kubectl rollout status deployment/argocd-server -n argocd

echo "==> Applying root App of Apps..."
kubectl apply -f "${REPO_ROOT}/bootstrap/argocd/root-app.yaml"

echo ""
echo "Done! ArgoCD is available at http://<node-ip>:30080"
echo "Default admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
