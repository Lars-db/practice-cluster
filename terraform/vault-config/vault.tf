# Configures Vault's Kubernetes auth method, a KV v2 mount, and a read-only
# policy/role so External Secrets Operator can pull secrets at sync time.
# Run this AFTER Vault is deployed (via ArgoCD) and manually unsealed -
# see scripts/vault-init.sh and docs/secrets-management.md.

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc:443"
}

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "KV v2 engine for application secrets synced by External Secrets Operator"
}

resource "vault_policy" "eso" {
  name = "eso-policy"

  policy = <<EOT
path "secret/data/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "eso" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "eso-role"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_ttl                        = 3600
  token_policies                   = ["eso-policy"]

  depends_on = [vault_policy.eso]
}

# Vault's Kubernetes auth method uses the TokenReview API to validate the
# ESO service account token - it needs the cluster-wide auth-delegator role.
resource "kubernetes_cluster_role_binding" "vault_auth_delegator" {
  metadata {
    name = "vault-external-secrets-auth-delegator"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets"
    namespace = "external-secrets"
  }
}
