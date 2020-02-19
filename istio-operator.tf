locals {
  istio_operator = merge(
    {
      enabled = false
    },
    var.istio_operator
  )
}

data "kubectl_file_documents" "istio_operator" {
  count   = local.istio_operator["enabled"] ? 1 : 0
  content = file("./templates/istio_operator.yaml")
}

resource "kubectl_manifest" "istio_operator" {
  count     = local.istio_operator["enabled"] ? length(data.kubectl_file_documents.istio_operator[0].documents) : 0
  yaml_body = element(data.kubectl_file_documents.istio_operator[0].documents, count.index)
}
