# practice-cluster

A locally hosted Kubernetes cluster built as a hands-on learning environment and portfolio project. It demonstrates GitOps principles using ArgoCD, Helm-based application packaging, and Terraform-managed infrastructure — all running on a single node.

The cluster ships with the [Istio Bookinfo](https://istio.io/latest/docs/examples/bookinfo/) sample application: a small polyglot microservices app (Python, Ruby, Java, Node.js) that is a practical target for practicing service mesh configuration, traffic management, and observability.

Secrets are never stored in plaintext in Git. **HashiCorp Vault** + **External Secrets Operator** provide repo-wide secrets management — see [`docs/secrets-management.md`](docs/secrets-management.md) for the architecture and the workflow for adding new secrets to any app.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Accessing the Applications](#accessing-the-applications)
- [Secrets Management](#secrets-management)
- [Adding a New Application](#adding-a-new-application)
- [Tearing Down](#tearing-down)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Local Node                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   Kubernetes Cluster                 │  │
│  │                                                      │  │
│  │   ┌─────────────┐        ┌──────────────────────┐   │  │
│  │   │   ArgoCD     │──watch─▶   apps/ (App of Apps) │  │  │
│  │   │  (argocd ns) │        │   Helm chart          │  │  │
│  │   └──────┬───────┘        └──────────┬───────────┘   │  │
│  │          │ deploys                   │ declares       │  │
│  │          ▼                           ▼                │  │
│  │   ┌───────────────┐  ┌──────────────┐  ┌───────────┐ │  │
│  │   │ Vault          │◀─│ External      │  │ bookinfo   │ │  │
│  │   │ (vault ns)     │  │ Secrets       │  │ namespace  │ │  │
│  │   │ KV v2 secrets  │─▶│ Operator      │─▶│            │ │  │
│  │   └───────────────┘  │ (eso ns)      │  │ productpage│ │  │
│  │                       └──────────────┘  │  ├─▶details │ │  │
│  │                                          │  └─▶reviews │ │  │
│  │                                          │      └▶ratings│ │
│  │                                          └───────────┘ │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         ▲
         │ terraform apply (namespaces, providers)
         │
   ┌─────┴──────┐
   │  Terraform  │
   │  local env  │
   └────────────┘
```

**GitOps flow:** every change merged to `main` is automatically detected by ArgoCD and reconciled in the cluster. The Git repository is the single source of truth.

---

## Tech Stack

| Tool | Role |
|---|---|
| **Kubernetes** | Container orchestration (single-node, local) |
| **Terraform** | Provisions namespaces and configures Kubernetes/Helm providers |
| **Helm** | Packages applications as reusable, configurable charts |
| **ArgoCD** | GitOps operator — continuously syncs cluster state to this repo |
| **HashiCorp Vault** | Secret store — single source of truth for sensitive values, never Git |
| **External Secrets Operator** | Syncs Vault secrets into native Kubernetes `Secret` objects at sync time |
| **Bookinfo** | Demo microservices app (Istio sample) for practice |

---

## Repository Structure

```
practice-cluster/
│
├── terraform/
│   ├── modules/                  # Reusable Terraform modules (extend as needed)
│   ├── envs/
│   │   └── local/
│   │       ├── main.tf           # Kubernetes + Helm provider configuration
│   │       ├── namespaces.tf     # Creates argocd, bookinfo, vault, external-secrets namespaces
│   │       ├── variables.tf      # Input variables (e.g. kubeconfig context)
│   │       └── outputs.tf        # Output values
│   └── vault-config/             # Configures Vault (auth/KV/policy) - applied separately, after Vault is unsealed
│       ├── main.tf               # Vault + Kubernetes provider configuration
│       ├── variables.tf          # vault_addr, vault_token (via TF_VAR_vault_token)
│       └── vault.tf              # Kubernetes auth method, KV v2 mount, ESO policy/role
│
├── bootstrap/
│   └── argocd/
│       ├── values.yaml           # Helm values for the ArgoCD installation
│       └── root-app.yaml         # The "root" ArgoCD Application (App of Apps entry point)
│
├── apps/                         # App of Apps Helm chart
│   ├── Chart.yaml
│   ├── values.yaml               # Toggle applications on/off, set namespaces
│   └── templates/
│       ├── bookinfo.yaml         # ArgoCD Application manifest for bookinfo
│       ├── vault.yaml            # ArgoCD Application for Vault (remote Helm chart source)
│       ├── external-secrets.yaml # ArgoCD Application for External Secrets Operator
│       └── secrets-config.yaml   # ArgoCD Application for the secrets-config chart
│
├── charts/                       # Helm charts for each application
│   ├── bookinfo/
│   │   ├── Chart.yaml
│   │   ├── values.yaml           # Image tags, replica counts, service ports
│   │   └── templates/
│   │       ├── productpage.yaml  # Frontend service (Python)
│   │       ├── details.yaml      # Book details service (Ruby)
│   │       ├── reviews.yaml      # Review aggregator service (Java)
│   │       ├── ratings.yaml      # Star ratings service (Node.js)
│   │       └── external-secret.yaml  # Syncs a demo Vault secret into productpage
│   └── secrets-config/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           └── cluster-secret-store.yaml  # ClusterSecretStore wiring ESO to Vault
│
├── cluster/
│   └── namespaces/               # Raw namespace manifests (reference / fallback)
│       ├── argocd.yaml
│       ├── bookinfo.yaml
│       ├── vault.yaml
│       └── external-secrets.yaml
│
├── scripts/
│   ├── bootstrap.sh              # Installs ArgoCD and applies the root app
│   ├── vault-init.sh             # One-time Vault initialize + unseal helper
│   └── teardown.sh               # Removes all apps and ArgoCD from the cluster
│
└── docs/
    └── secrets-management.md     # Vault + ESO architecture and secret-adding workflow
```

---

## How It Works

This cluster is built around the **App of Apps** GitOps pattern:

1. **Terraform** runs first to create namespaces and configure providers against the local kubeconfig.

2. **ArgoCD** is installed via Helm into the `argocd` namespace using the values in `bootstrap/argocd/values.yaml`.

3. The **root Application** (`bootstrap/argocd/root-app.yaml`) is applied once manually. It points ArgoCD at the `apps/` directory in this repo.

4. ArgoCD renders the **`apps/` Helm chart**, which produces one ArgoCD `Application` resource per entry in `apps/values.yaml` (currently: `vault`, `external-secrets`, `secrets-config`, `bookinfo`). `argocd.argoproj.io/sync-wave` annotations make sure Vault and ESO come up before `secrets-config` (which needs ESO's CRDs), which comes up before `bookinfo` (which references the `ClusterSecretStore` `secrets-config` declares). See [Secrets Management](#secrets-management).

5. Each child Application points ArgoCD at a chart in `charts/`. ArgoCD deploys and continuously reconciles it.

6. From this point on, **any `git push` to `main` is automatically applied to the cluster** — no manual `kubectl apply` needed.

```
Git push
   └─▶ ArgoCD detects change
          └─▶ Renders apps/ Helm chart
                 └─▶ Syncs child Applications
                        └─▶ Deploys/updates charts/bookinfo
```

---

## Prerequisites

- A running local Kubernetes cluster. Recommended options for a single node:
  - [k3s](https://k3s.io/) — lightweight, production-grade
  - [k3d](https://k3d.io/) — k3s in Docker, easy to reset
  - [minikube](https://minikube.sigs.k8s.io/) — well-documented, beginner-friendly
- `kubectl` configured and pointing at the cluster (`~/.kube/config`)
- [Helm](https://helm.sh/docs/intro/install/) v3+
- [Terraform](https://developer.hashicorp.com/terraform/install) v1.3+
- Git (repo cloned and remote set)

---

## Getting Started

### 1. Clone and configure

```bash
git clone https://github.com/Lars-db/practice-cluster.git
cd practice-cluster
```

> Forking this repo? Update the repo URL in both `bootstrap/argocd/root-app.yaml` (`spec.source.repoURL`) and `apps/values.yaml` (`repoURL`) to point at your own fork before bootstrapping.

### 2. Provision namespaces with Terraform

```bash
cd terraform/envs/local
terraform init
terraform apply
```

This creates the `argocd` and `bookinfo` namespaces in the cluster.

### 3. Bootstrap ArgoCD

```bash
cd ../../..   # back to repo root
./scripts/bootstrap.sh
```

This script:
- Adds the ArgoCD Helm repo
- Installs ArgoCD into the `argocd` namespace
- Waits for the deployment to be ready
- Applies the root App of Apps

ArgoCD will then automatically deploy Vault, External Secrets Operator, `secrets-config`, and bookinfo within a few minutes.

### 4. Bootstrap secrets management

Vault comes up sealed and unconfigured - this is a manual, one-time step
(see [Secrets Management](#secrets-management) for why):

```bash
./scripts/vault-init.sh
export TF_VAR_vault_token=<root token printed above>
cd terraform/vault-config && terraform init && terraform apply && cd ../..
kubectl -n vault exec vault-0 -- vault kv put secret/bookinfo/productpage password=demo123
```

Until this is done, `bookinfo`'s `productpage` pod will not become `Ready` -
it depends on a secret synced from Vault. Full details and the workflow for
adding new secrets are in [`docs/secrets-management.md`](docs/secrets-management.md).

---

## Accessing the Applications

### Bookinfo (productpage)

```
http://<node-ip>:30090/productpage
```

The productpage calls the other services internally and renders a book review page — useful for observing inter-service traffic.

### ArgoCD UI

```
http://<node-ip>:30080
```

Retrieve the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

> For local clusters you can also use `kubectl port-forward` if NodePort access is not available:
> ```bash
> kubectl port-forward svc/argocd-server -n argocd 8080:80
> # then visit http://localhost:8080
> ```

### Vault UI

Vault's chart doesn't expose a NodePort by default - use `kubectl port-forward`:

```bash
kubectl port-forward svc/vault -n vault 8200:8200
# then visit http://localhost:8200 and log in with the root token
```

---

## Secrets Management

Secrets are never committed to Git in plaintext. **HashiCorp Vault** is the
single source of truth for sensitive values; **External Secrets Operator**
syncs them into real Kubernetes `Secret` objects that apps consume normally.

See [`docs/secrets-management.md`](docs/secrets-management.md) for the full
architecture, the one-time bootstrap steps, and the step-by-step workflow for
adding a new secret to any app.

---

## Adding a New Application

1. Create a Helm chart under `charts/<app-name>/`
2. Add an ArgoCD Application template under `apps/templates/<app-name>.yaml` (copy `bookinfo.yaml` as a reference)
3. Add an entry to `apps/values.yaml`:
   ```yaml
   apps:
     bookinfo:
       enabled: true
       namespace: bookinfo
     my-new-app:          # <-- add this
       enabled: true
       namespace: my-new-app
   ```
4. If the app needs a secret, follow the workflow in
   [`docs/secrets-management.md`](docs/secrets-management.md) — write the
   value to Vault, add an `ExternalSecret` manifest, consume the resulting
   `Secret` in your Deployment. Never commit a plaintext value.
5. Commit and push to `main` — ArgoCD handles the rest.

---

## Tearing Down

```bash
./scripts/teardown.sh
```

This removes the root Application, uninstalls ArgoCD, and deletes the `argocd`, `bookinfo`, `vault`, and `external-secrets` namespaces (which also destroys Vault's data - there's nothing to preserve in a learning cluster, but note this before reusing it for anything real).

To also destroy the Terraform-managed resources:

```bash
cd terraform/envs/local
terraform destroy
```

If you ran `terraform apply` in `terraform/vault-config`, that state now
refers to a Vault that no longer exists — see the note printed by
`teardown.sh`.
