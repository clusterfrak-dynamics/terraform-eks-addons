locals {
  values_cert_manager = <<VALUES
image:
  tag: ${var.cert_manager["version"]}
rbac:
  create: true
podSecurityPolicy:
  enabled: false
podAnnotations:
  iam.amazonaws.com/role: "${var.cert_manager["enabled"] && var.cert_manager["create_iam_resources_kiam"] ? aws_iam_role.eks-cert-manager-kiam[0].arn : ""}"
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "${var.cert_manager["enabled"] && var.cert_manager["create_iam_resources_irsa"] ? module.iam_assumable_role_cert_manager.this_iam_role_arn : ""}"
VALUES

}

module "iam_assumable_role_cert_manager" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> v2.6.0"
  create_role                   = var.cert_manager["enabled"] && var.cert_manager["create_iam_resources_irsa"]
  role_name                     = "tf-eks-${var.cluster-name}-cert-manager-irsa"
  provider_url                  = replace(var.eks["cluster_oidc_issuer_url"], "https://", "")
  role_policy_arns              = var.cert_manager["enabled"] && var.cert_manager["create_iam_resources_irsa"] ? [aws_iam_policy.eks-cert-manager[0].arn] : []
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.cert_manager["namespace"]}:cert-manager"]
}

resource "aws_iam_policy" "eks-cert-manager" {
  count  = var.cert_manager["enabled"] && (var.cert_manager["create_iam_resources_kiam"] || var.cert_manager["create_iam_resources_irsa"]) ? 1 : 0
  name   = "tf-eks-${var.cluster-name}-cert-manager"
  policy = var.cert_manager["iam_policy_override"] == "" ? data.aws_iam_policy_document.cert_manager.json : var.cert_manager["iam_policy_override"]
}

data "aws_iam_policy_document" "cert_manager" {
  statement {
    effect = "Allow"

    actions = [
      "route53:GetChange"
    ]

    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]

    resources = ["arn:aws:route53:::hostedzone/*"]

  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListHostedZonesByName"
    ]

    resources = ["*"]

  }
}


resource "aws_iam_role" "eks-cert-manager-kiam" {
  name  = "tf-eks-${var.cluster-name}-cert-manager-kiam"
  count = var.cert_manager["enabled"] && var.cert_manager["create_iam_resources_kiam"] ? 1 : 0

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.eks-kiam-server-role[count.index].arn}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

}

resource "aws_iam_role_policy_attachment" "eks-cert-manager-kiam" {
  count      = var.cert_manager["enabled"] && var.cert_manager["create_iam_resources_kiam"] ? 1 : 0
  role       = aws_iam_role.eks-cert-manager-kiam[count.index].name
  policy_arn = aws_iam_policy.eks-cert-manager[count.index].arn
}

resource "kubernetes_namespace" "cert_manager" {
  count = var.cert_manager["enabled"] ? 1 : 0

  metadata {
    annotations = {
      "iam.amazonaws.com/permitted"           = "${var.cert_manager["create_iam_resources_kiam"] ? aws_iam_role.eks-cert-manager-kiam[0].arn : "^$"}"
      "certmanager.k8s.io/disable-validation" = "true"
    }

    labels = {
      name = var.cert_manager["namespace"]
    }

    name = var.cert_manager["namespace"]
  }
}

resource "helm_release" "cert_manager" {
  count         = var.cert_manager["enabled"] ? 1 : 0
  repository    = data.helm_repository.jetstack.metadata[0].name
  name          = "cert-manager"
  chart         = "cert-manager"
  version       = var.cert_manager["chart_version"]
  timeout       = var.cert_manager["timeout"]
  force_update  = var.cert_manager["force_update"]
  recreate_pods = var.cert_manager["recreate_pods"]
  wait          = var.cert_manager["wait"]
  values = concat(
    [local.values_cert_manager],
    [var.cert_manager["extra_values"]],
  )
  namespace = kubernetes_namespace.cert_manager.*.metadata.0.name[count.index]

  depends_on = [
    helm_release.kiam,
    kubectl_manifest.cert_manager_crds
  ]
}

data "http" "cert_manager_crds" {
  count = var.cert_manager["enabled"] ? 1 : 0
  url   = "https://raw.githubusercontent.com/jetstack/cert-manager/${var.cert_manager["version"]}/deploy/manifests/00-crds.yaml"
}

resource "kubectl_manifest" "cert_manager_crds" {
  count     = var.cert_manager["enabled"] ? 1 : 0
  yaml_body = data.http.cert_manager_crds[0].body
}

data "kubectl_path_documents" "cert_manager_cluster_issuers" {
  pattern = "./templates/cert-manager-cluster-issuers.yaml"
  vars = {
    acme_email = var.cert_manager["acme_email"]
    aws_region = var.aws["region"]
  }
}

resource "kubectl_manifest" "cert_manager_cluster_issuers" {
  count      = (var.cert_manager["enabled"] ? 1 : 0) * (var.cert_manager["enable_default_cluster_issuers"] ? 1 : 0) * length(data.kubectl_path_documents.cert_manager_cluster_issuers.documents)
  yaml_body  = element(data.kubectl_path_documents.cert_manager_cluster_issuers.documents, count.index)
  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_network_policy" "cert_manager_default_deny" {
  count = var.cert_manager["enabled"] && var.cert_manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.cert_manager.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.cert_manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "cert_manager_allow_namespace" {
  count = var.cert_manager["enabled"] && var.cert_manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.cert_manager.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.cert_manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.cert_manager.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
