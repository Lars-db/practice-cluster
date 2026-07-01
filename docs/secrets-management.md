# Secrets Management

This repo never stores plaintext secrets in Git. Secrets live in **HashiCorp
Vault**, running in-cluster, and get synced into real Kubernetes `Secret`
objects by the **External Secrets Operator (ESO)** at sync time. Only
non-sensitive *references* to secrets (paths, key names) are committed.

## Architecture

```
Git (this repo)
  └─ ArgoCD Applications: vault, external-secrets, secrets-config, bookinfo
         │
         ▼
  ┌──────────────┐        Kubernetes auth       ┌────────────────────┐
  │ Vault         │◀──────────────────────────── │ External Secrets    │
  │ (vault ns)    │                              │ Operator (eso ns)   │
  │ KV v2: secret/│──── ClusterSecretStore ─────▶│                     │
  └──────────────┘        "vault-backend"        └─────────┬───────────┘
                                                            │ ExternalSecret
                                                            ▼
                                                 Kubernetes Secret object
                                                 (e.g. productpage-secret)
                                                            │
                                                            ▼
                                                    consuming Deployment
```

- **Vault** (`apps/templates/vault.yaml`) runs standalone with Raft integrated
  storage - no external Consul needed. Deployed like any other app via the
  App-of-Apps pattern, but sourced directly from HashiCorp's Helm repo
  instead of a local chart path.
- **External Secrets Operator** (`apps/templates/external-secrets.yaml`) is
  deployed the same way, from the upstream ESO Helm repo.
- **`charts/secrets-config`** is a small local chart (git-path sourced, like
  `charts/bookinfo`) that declares the cluster-wide `ClusterSecretStore`
  wiring ESO to Vault via Kubernetes auth.
- **Vault's own configuration** (Kubernetes auth method, KV v2 mount, the
  read-only policy/role ESO authenticates as) is managed as code in
  `terraform/vault-config/` - kept as a *separate* Terraform root from
  `terraform/envs/local` because it needs a live, unsealed Vault and a
  `TF_VAR_vault_token` that must never be committed.

## One-time cluster bootstrap

After `./scripts/bootstrap.sh` has run and the `vault` Application has
synced:

```bash
# 1. Initialize and unseal Vault (single key share - homelab, not HA)
./scripts/vault-init.sh
# Save the printed unseal key + root token somewhere safe (password manager).
# They are never written to disk by this script.

# 2. Configure Vault's kubernetes auth / KV engine / ESO policy as code
export TF_VAR_vault_token=<root token from step 1>
cd terraform/vault-config
terraform init
terraform apply
cd ../..
```

Until these steps are done, the `vault` Application will show as
`Progressing`/`Degraded` in ArgoCD (Vault is sealed, so its readiness probe
fails - expected) and any app whose Deployment references a Vault-backed
secret (e.g. `bookinfo/productpage`) will not become `Ready` (its
`ExternalSecret` can't sync yet). This is normal for a freshly bootstrapped
cluster.

**Note:** since Vault uses the default Shamir seal (no auto-unseal
configured), if the `vault-0` pod restarts or is rescheduled, it comes back
up sealed and needs `vault operator unseal <key>` run again manually. This is
an accepted tradeoff for a single-node learning cluster - a production setup
would use an auto-unseal mechanism (cloud KMS, etc).

## Adding a new secret to an existing or new app

1. **Write the secret to Vault** (KV v2, mounted at `secret/`):
   ```bash
   kubectl -n vault exec vault-0 -- vault kv put secret/<app-name>/<secret-name> <key>=<value>
   ```
   Pick a path convention of `<app-name>/<secret-name>` to keep Vault
   organized as more apps are added.

2. **Add an `ExternalSecret` manifest** to the app's chart (see
   `charts/bookinfo/templates/external-secret.yaml` for a working example):
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: <app-name>-secret
     namespace: <app-namespace>
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault-backend
       kind: ClusterSecretStore
     target:
       name: <app-name>-secret
       creationPolicy: Owner
     data:
       - secretKey: <key>
         remoteRef:
           key: <app-name>/<secret-name>
           property: <key>
   ```

3. **Consume the resulting `Secret`** in your Deployment the normal
   Kubernetes way (`env[].valueFrom.secretKeyRef` or `envFrom`), exactly as
   `charts/bookinfo/templates/productpage.yaml` does.

4. Commit the `ExternalSecret` manifest and chart changes - nothing sensitive
   is in Git, only the reference to where the value lives in Vault.

## Why every ArgoCD Application depends on the ones before it

`apps/templates/secrets-config.yaml` and `apps/templates/bookinfo.yaml` carry
`argocd.argoproj.io/sync-wave` annotations (`"1"` and `"2"` respectively) so
that Vault and ESO's CRDs exist before the `ClusterSecretStore` is applied,
and the `ClusterSecretStore` exists before any app tries to reference it in
an `ExternalSecret`.
