variable "vault_addr" {
  description = "Address of the Vault server (e.g. via kubectl port-forward svc/vault -n vault 8200:8200)"
  type        = string
  default     = "http://127.0.0.1:8200"
}

variable "vault_token" {
  description = "Vault root/admin token, supplied via TF_VAR_vault_token - never committed"
  type        = string
  sensitive   = true
}

variable "kube_context" {
  description = "The kubeconfig context to use for the local cluster"
  type        = string
  default     = "default"
}
