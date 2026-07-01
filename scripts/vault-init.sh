#!/usr/bin/env bash
# One-time helper: initialize and unseal Vault after ArgoCD has deployed it.
# Uses a single key share/threshold since this is a single-node homelab
# cluster, not a production HA deployment.
#
# The unseal key and root token are printed to the terminal ONLY - they are
# never written to disk. Store them in a password manager; you'll need the
# root token again for the terraform/vault-config step, and the unseal key
# again any time the vault-0 pod restarts.
set -euo pipefail

NAMESPACE="vault"
POD="vault-0"

echo "==> Waiting for ${POD} to exist in namespace ${NAMESPACE}..."
kubectl -n "${NAMESPACE}" wait --for=condition=PodScheduled "pod/${POD}" --timeout=180s

if kubectl -n "${NAMESPACE}" exec "${POD}" -- vault status -format=json 2>/dev/null | grep -q '"initialized": true'; then
  echo "==> Vault is already initialized."
else
  echo "==> Initializing Vault (1 key share, 1 key threshold - homelab only)..."
  kubectl -n "${NAMESPACE}" exec "${POD}" -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > /tmp/vault-init-output.json

  UNSEAL_KEY=$(grep -o '"unseal_keys_b64":\["[^"]*"' /tmp/vault-init-output.json | cut -d'"' -f4)
  ROOT_TOKEN=$(grep -o '"root_token": *"[^"]*"' /tmp/vault-init-output.json | cut -d'"' -f4)
  rm -f /tmp/vault-init-output.json

  echo ""
  echo "=================================================================="
  echo " SAVE THESE NOW - they are not written anywhere else:"
  echo ""
  echo "   Unseal key: ${UNSEAL_KEY}"
  echo "   Root token: ${ROOT_TOKEN}"
  echo ""
  echo "=================================================================="
  echo ""
fi

read -rp "Enter the unseal key to unseal ${POD}: " UNSEAL_KEY_INPUT
kubectl -n "${NAMESPACE}" exec "${POD}" -- vault operator unseal "${UNSEAL_KEY_INPUT}"

echo "==> Vault status:"
kubectl -n "${NAMESPACE}" exec "${POD}" -- vault status

echo ""
echo "Next: export TF_VAR_vault_token=<root token>, then run:"
echo "  cd terraform/vault-config && terraform init && terraform apply"
