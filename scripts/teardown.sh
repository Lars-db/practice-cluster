#!/usr/bin/env bash
# Tear down all ArgoCD applications and ArgoCD itself
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Deleting root App of Apps..."
kubectl delete -f "${REPO_ROOT}/bootstrap/argocd/root-app.yaml" --ignore-not-found

echo "==> Uninstalling ArgoCD..."
helm uninstall argocd -n argocd || true

echo "==> Deleting namespaces..."
kubectl delete namespace argocd --ignore-not-found
kubectl delete namespace bookinfo --ignore-not-found

echo "Done."
