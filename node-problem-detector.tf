locals {
  values_npd = <<VALUES
rbac:
  pspEnabled: true
image:
  tag: ${var.npd["version"]}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/node
          operator: Exists
tolerations:
  - operator: Exists
VALUES

}

resource "kubernetes_namespace" "node_problem_detector" {
  count = var.npd["enabled"] ? 1 : 0

  metadata {
    labels = {
      name = var.npd["namespace"]
    }

    name = var.npd["namespace"]
  }
}

resource "helm_release" "node_problem_detector" {
  count         = var.npd["enabled"] ? 1 : 0
  repository    = data.helm_repository.stable.metadata[0].name
  name          = "node-problem-detector"
  chart         = "node-problem-detector"
  version       = var.npd["chart_version"]
  timeout       = var.npd["timeout"]
  force_update  = var.npd["force_update"]
  recreate_pods = var.npd["recreate_pods"]
  wait          = var.npd["wait"]
  values        = concat([local.values_npd], [var.npd["extra_values"]])
  namespace     = kubernetes_namespace.node_problem_detector.*.metadata.0.name[count.index]
}

resource "kubernetes_network_policy" "npd_default_deny" {
  count = (var.npd["enabled"] ? 1 : 0) * (var.npd["default_network_policy"] ? 1 : 0)

  metadata {
    name      = "${kubernetes_namespace.node_problem_detector.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.node_problem_detector.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "npd_allow_namespace" {
  count = (var.npd["enabled"] ? 1 : 0) * (var.npd["default_network_policy"] ? 1 : 0)

  metadata {
    name      = "${kubernetes_namespace.node_problem_detector.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.node_problem_detector.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.node_problem_detector.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

