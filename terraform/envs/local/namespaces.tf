resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace" "bookinfo" {
  metadata {
    name = "bookinfo"
    labels = {
      "app" = "bookinfo"
    }
  }
}
