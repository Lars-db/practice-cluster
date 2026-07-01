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
kubectl delete namespace vault --ignore-not-found
kubectl delete namespace external-secrets --ignore-not-found

echo ""
echo "Note: if you ran 'terraform apply' in terraform/vault-config, that state"
echo "now points at a Vault that no longer exists. Run 'terraform state list'"
echo "and 'terraform state rm <resource>' for each resource (or just delete"
echo "terraform/vault-config/terraform.tfstate*) before reusing that directory."
echo ""
echo "Done."
