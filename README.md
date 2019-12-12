# terraform-kubernetes-addons

[![Build Status](https://travis-ci.com/clusterfrak-dynamics/terraform-kubernetes-addons.svg?branch=master)](https://travis-ci.com/clusterfrak-dynamics/terraform-kubernetes-addons)
[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/terraform-kubernetes-addons)

## About

Provides various addons that are often used on Kubernetes

## Main features

* Common addons with associated IAM permissions if needed:
  * [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler): scale worker nodes based on workload.
  * [external-dns](https://github.com/kubernetes-incubator/external-dns): sync ingress and service records in route53.
  * [cert-manager](https://github.com/jetstack/cert-manager): automatically generate TLS certificates, supports ACME v2.
  * [kiam](https://github.com/uswitch/kiam): prevents pods to access EC2 metadata and enables pods to assume specific AWS IAM roles.
  * [nginx-ingress](https://github.com/kubernetes/ingress-nginx): processes *Ingress* object and acts as a HTTP/HTTPS proxy (compatible with cert-manager).
  * [metrics-server](https://github.com/kubernetes-incubator/metrics-server): enable metrics API and horizontal pod scaling (HPA).
  * [prometheus-operator](https://github.com/coreos/prometheus-operator): Monitoring / Alerting / Dashboards.
  * [virtual-kubelet](https://github.com/coreos/prometheus-operator): enables using ECS Fargate as a provider to run workload without EC2 instances.
  * [fluentd-cloudwatch](https://github.com/helm/charts/tree/master/incubator/fluentd-cloudwatch): forwards logs to AWS Cloudwatch.
  * [node-problem-detector](https://github.com/kubernetes/node-problem-detector): Forwards node problems to Kubernetes events
  * [flux](https://github.com/weaveworks/flux): Continous Delivery with Gitops workflow.
  * [sealed-secrets](https://github.com/bitnami-labs/sealed-secrets): Technology agnostic, store secrets on git.
  * [istio](https://istio.io): Service mesh for Kubernetes.
  * [cni-metrics-helper](https://docs.aws.amazon.com/eks/latest/userguide/cni-metrics-helper.html): Provides cloudwatch metrics for VPC CNI plugins.
  * [kong](https://konghq.com/kong): API Gateway ingress controller.
  * [rancher](https://rancher.com/): UI for easy cluster management.
  * [keycloak](https://www.keycloak.org/) : Identity and access management

## Requirements

* [Terraform](https://www.terraform.io/intro/getting-started/install.html)
* [Terragrunt](https://github.com/gruntwork-io/terragrunt#install-terragrunt)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [helm](https://helm.sh/)
* [aws-iam-authenticator](https://github.com/kubernetes-sigs/aws-iam-authenticator)

## Documentation

User guides, feature documentation and examples are available [here](https://clusterfrak-dynamics.github.io/teks/)

## About Kiam

Kiam prevents pods from accessing EC2 instances IAM role and therefore using the instances role to perform actions on AWS. It also allows pods to assume specific IAM roles if needed. To do so `kiam-agent` acts as an iptables proxy on nodes. It intercepts requests made to EC2 metadata and redirect them to a `kiam-server` that fetches IAM credentials and pass them to pods.

Kiam is running with an IAM user and use a secret key and a access key (AK/SK).

### Addons that require specific IAM permissions

Some addons interface with AWS API, for example:

* `cluster-autoscaler`
* `external-dns`
* `cert-manager`
* `virtual-kubelet`
* `cni-metric-helper`
