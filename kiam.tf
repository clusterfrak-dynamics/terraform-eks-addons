locals {
  values_kiam = <<VALUES
agent:
  tlsFiles:
    key: ${base64encode(join(",", tls_private_key.kiam_agent_key.*.private_key_pem))}
    cert: ${base64encode(join(",", tls_locally_signed_cert.kiam_agent_crt.*.cert_pem))}
    ca: ${base64encode(join(",", tls_self_signed_cert.kiam_ca_crt.*.cert_pem))}
  image:
    tag: ${var.kiam["version"]}
  nodeSelector:
    node-role.kubernetes.io/node: ""
  extraArgs:
    whitelist-route-regexp: "/latest"
  host:
    interface: "eni+"
    iptables: true
  updateStrategy: "RollingUpdate"
  extraHostPathMounts:
    - name: ssl-certs
      mountPath: /etc/ssl/certs
      hostPath: /etc/pki/ca-trust/extracted/pem
      readOnly: true
  tolerations: ${var.kiam["server_use_host_network"] ? "[{'operator': 'Exists'}]" : "[]"}
server:
  useHostNetwork: ${var.kiam["server_use_host_network"]}
  probes:
    serverAddress: "127.0.0.1"
  tlsFiles:
    key: ${base64encode(join(",", tls_private_key.kiam_server_key.*.private_key_pem))}
    cert: ${base64encode(join(",", tls_locally_signed_cert.kiam_server_crt.*.cert_pem))}
    ca: ${base64encode(join(",", tls_self_signed_cert.kiam_ca_crt.*.cert_pem))}
  image:
    tag: ${var.kiam["version"]}
  nodeSelector:
    node-role.kubernetes.io/controller: ""
  tolerations:
    - operator: Exists
      effect: NoSchedule
      key: "node-role.kubernetes.io/controller"
  assumeRoleArn: ${join(",",data.terraform_remote_state.eks.*.kiam-server-role-arn[0])}
  extraHostPathMounts:
    - name: ssl-certs
      mountPath: /etc/ssl/certs
      hostPath: /etc/pki/ca-trust/extracted/pem
      readOnly: true
VALUES
}

resource "kubernetes_namespace" "kiam" {
  count = "${var.kiam["enabled"] ? 1 : 0 }"

  metadata {
    labels {
      name = "${var.kiam["namespace"]}"
    }

    name = "${var.kiam["namespace"]}"
  }
}

resource "helm_release" "kiam" {
  count      = "${var.kiam["enabled"] ? 1 : 0 }"
  repository = "${data.helm_repository.stable.metadata.0.name}"
  name       = "kiam"
  chart      = "kiam"
  version    = "${var.kiam["chart_version"]}"
  values     = ["${concat(list(local.values_kiam),list(var.kiam["extra_values"]))}"]
  namespace  = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}"
}

resource "tls_private_key" "kiam_ca_key" {
  count     = "${var.kiam["enabled"] ? 1 : 0 }"
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "kiam_ca_crt" {
  count           = "${var.kiam["enabled"] ? 1 : 0 }"
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.kiam_ca_key.private_key_pem}"

  subject {
    common_name  = "kiam-ca"
    organization = "KIAM"
  }

  is_ca_certificate     = true
  validity_period_hours = 87360

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
  ]
}

resource "tls_private_key" "kiam_agent_key" {
  count     = "${var.kiam["enabled"] ? 1 : 0 }"
  algorithm = "RSA"
}

resource "tls_cert_request" "kiam_agent_csr" {
  count           = "${var.kiam["enabled"] ? 1 : 0 }"
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.kiam_agent_key.private_key_pem}"

  subject {
    common_name  = "kiam-agent"
    organization = "KIAM"
  }
}

resource "tls_locally_signed_cert" "kiam_agent_crt" {
  count              = "${var.kiam["enabled"] ? 1 : 0 }"
  cert_request_pem   = "${tls_cert_request.kiam_agent_csr.cert_request_pem}"
  ca_key_algorithm   = "RSA"
  ca_private_key_pem = "${tls_private_key.kiam_ca_key.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.kiam_ca_crt.cert_pem}"

  validity_period_hours = 87360

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

resource "tls_private_key" "kiam_server_key" {
  count     = "${var.kiam["enabled"] ? 1 : 0 }"
  algorithm = "RSA"
}

resource "tls_cert_request" "kiam_server_csr" {
  count           = "${var.kiam["enabled"] ? 1 : 0 }"
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.kiam_server_key.private_key_pem}"

  subject {
    common_name  = "kiam-server"
    organization = "KIAM"
  }

  dns_names = [
    "kiam-server",
    "kiam-server:443",
  ]

  ip_addresses = [
    "127.0.0.1",
  ]
}

resource "tls_locally_signed_cert" "kiam_server_crt" {
  count              = "${var.kiam["enabled"] ? 1 : 0 }"
  cert_request_pem   = "${tls_cert_request.kiam_server_csr.cert_request_pem}"
  ca_key_algorithm   = "RSA"
  ca_private_key_pem = "${tls_private_key.kiam_ca_key.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.kiam_ca_crt.cert_pem}"

  validity_period_hours = 87360

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

resource "kubernetes_network_policy" "kiam_default_deny" {
  count = "${var.kiam["enabled"] * var.kiam["default_network_policy"]}"

  metadata {
    name      = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}-default-deny"
    namespace = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}"
  }

  spec {
    pod_selector = {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "kiam_allow_namespace" {
  count = "${var.kiam["enabled"] * var.kiam["default_network_policy"]}"

  metadata {
    name      = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}"
  }

  spec {
    pod_selector {}

    ingress = [
      {
        from = [
          {
            namespace_selector {
              match_labels = {
                name = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}"
              }
            }
          },
        ]
      },
    ]

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "kiam_allow_requests" {
  count = "${var.kiam["enabled"] * var.kiam["default_network_policy"]}"

  metadata {
    name      = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}-allow-requests"
    namespace = "${kubernetes_namespace.kiam.*.metadata.0.name[count.index]}"
  }

  spec {
    pod_selector {
      match_expressions {
        key      = "app"
        operator = "In"
        values   = ["kiam"]
      }

      match_expressions {
        key      = "component"
        operator = "In"
        values   = ["server"]
      }
    }

    ingress = [
      {
        ports = [
          {
            port     = "grpclb"
            protocol = "TCP"
          },
        ]

        from = [
          {
            namespace_selector = {}
            pod_selector       = {}
          },
        ]
      },
    ]

    policy_types = ["Ingress"]
  }
}

output "kiam_ca_crt" {
  value = "${tls_self_signed_cert.kiam_ca_crt.*.cert_pem}"
}

output "kiam_server_crt" {
  value = "${tls_locally_signed_cert.kiam_server_crt.*.cert_pem}"
}

output "kiam_agent_crt" {
  value = "${tls_locally_signed_cert.kiam_agent_crt.*.cert_pem}"
}
