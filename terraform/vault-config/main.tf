terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}
