# practice-cluster

A locally hosted Kubernetes cluster built as a hands-on learning environment and portfolio project. It demonstrates GitOps principles using ArgoCD, Helm-based application packaging, and Terraform-managed infrastructure — all running on a single node.

The cluster ships with the [Istio Bookinfo](https://istio.io/latest/docs/examples/bookinfo/) sample application: a small polyglot microservices app (Python, Ruby, Java, Node.js) that is a practical target for practicing service mesh configuration, traffic management, and observability.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Accessing the Applications](#accessing-the-applications)
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
│  │   ┌─────────────────────────────────────────────┐    │  │
│  │   │              bookinfo namespace              │    │  │
│  │   │                                              │    │  │
│  │   │  productpage ──▶ details                    │    │  │
│  │   │       │                                      │    │  │
│  │   │       └────────▶ reviews ──▶ ratings         │    │  │
│  │   │                                              │    │  │
│  │   └─────────────────────────────────────────────┘    │  │
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
| **Bookinfo** | Demo microservices app (Istio sample) for practice |

---

## Repository Structure

```
practice-cluster/
│
├── terraform/
│   ├── modules/                  # Reusable Terraform modules (extend as needed)
│   └── envs/
│       └── local/
│           ├── main.tf           # Kubernetes + Helm provider configuration
│           ├── namespaces.tf     # Creates argocd and bookinfo namespaces
│           ├── variables.tf      # Input variables (e.g. kubeconfig context)
│           └── outputs.tf        # Output values
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
│       └── bookinfo.yaml         # ArgoCD Application manifest for bookinfo
│
├── charts/                       # Helm charts for each application
│   └── bookinfo/
│       ├── Chart.yaml
│       ├── values.yaml           # Image tags, replica counts, service ports
│       └── templates/
│           ├── productpage.yaml  # Frontend service (Python)
│           ├── details.yaml      # Book details service (Ruby)
│           ├── reviews.yaml      # Review aggregator service (Java)
│           └── ratings.yaml      # Star ratings service (Node.js)
│
├── cluster/
│   └── namespaces/               # Raw namespace manifests (reference / fallback)
│       ├── argocd.yaml
│       └── bookinfo.yaml
│
├── scripts/
│   ├── bootstrap.sh              # Installs ArgoCD and applies the root app
│   └── teardown.sh               # Removes all apps and ArgoCD from the cluster
│
└── docs/                         # Additional documentation (architecture decisions, runbooks)
```

---

## How It Works

This cluster is built around the **App of Apps** GitOps pattern:

1. **Terraform** runs first to create namespaces and configure providers against the local kubeconfig.

2. **ArgoCD** is installed via Helm into the `argocd` namespace using the values in `bootstrap/argocd/values.yaml`.

3. The **root Application** (`bootstrap/argocd/root-app.yaml`) is applied once manually. It points ArgoCD at the `apps/` directory in this repo.

4. ArgoCD renders the **`apps/` Helm chart**, which produces one ArgoCD `Application` resource per entry in `apps/values.yaml` (currently: `bookinfo`).

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
git clone https://github.com/<your-user>/practice-cluster.git
cd practice-cluster
```

Update the repo URL in `bootstrap/argocd/root-app.yaml`:

```yaml
source:
  repoURL: https://github.com/<your-user>/practice-cluster.git  # <-- set this
```

Also update `apps/values.yaml`:

```yaml
repoURL: https://github.com/<your-user>/practice-cluster.git  # <-- set this
```

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

ArgoCD will then automatically deploy bookinfo within a minute or two.

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
4. Commit and push to `main` — ArgoCD handles the rest.

---

## Tearing Down

```bash
./scripts/teardown.sh
```

This removes the root Application, uninstalls ArgoCD, and deletes the `argocd` and `bookinfo` namespaces.

To also destroy the Terraform-managed resources:

```bash
cd terraform/envs/local
terraform destroy
```
