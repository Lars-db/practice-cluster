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
echo "=================================================================="
echo " Next: bootstrap secrets management (Vault + External Secrets)"
echo "=================================================================="
echo "1. Wait for the 'vault' Application to sync (kubectl -n argocd get application vault)"
echo "2. Run ./scripts/vault-init.sh to initialize and unseal Vault"
echo "3. export TF_VAR_vault_token=<root token from step 2>"
echo "4. cd terraform/vault-config && terraform init && terraform apply"
echo "5. Write a demo secret: vault kv put secret/bookinfo/productpage password=demo123"
echo "   (see docs/secrets-management.md for the full workflow)"
echo ""
