locals {
  istio_operator = merge(
    {
      enabled = false
    },
    var.istio_operator
  )
}

data "kubectl_path_documents" "istio_operator_crds" {
  count   = local.istio_operator["enabled"] ? 1 : 0
  pattern = "./templates/istio-operator/crds/*.yaml"
}

data "kubectl_path_documents" "istio_operator" {
  count   = local.istio_operator["enabled"] ? 1 : 0
  pattern = "./templates/istio-operator/*.yaml"
}

resource "kubectl_manifest" "istio_operator_crds" {
  count      = local.istio_operator["enabled"] ? length(data.kubectl_path_documents.istio_operator_crds[0].documents) : 0
  yaml_body  = element(data.kubectl_path_documents.istio_operator_crds[0].documents, count.index)
}

resource "kubectl_manifest" "istio_operator" {
  count     = local.istio_operator["enabled"] ? length(data.kubectl_path_documents.istio_operator[0].documents) : 0
  yaml_body = element(data.kubectl_path_documents.istio_operator[0].documents, count.index)

  depends_on = [
    kubectl_manifest.istio_operator_crds
  ]
}
