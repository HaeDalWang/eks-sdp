# Ingress NGINX를 설치할 네임스페이스
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

# 이미 존재하는 ACM 인증서가 있는지 확인
data "aws_acm_certificate" "service_domain" {
  domain      = local.service_domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Ingress NGINX
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_chart_version
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/ingress-nginx.yaml", {
      lb_acm_certificate_arn = data.aws_acm_certificate.service_domain.arn
      whitelist_source_range = join(",", local.whitelist_ip_range)
    })
  ]

  depends_on = [
    helm_release.karpenter
  ]
}

# Secret 객체 및 configmap 객체에 변경이 감지되면 Pod를 재생성해주는 라이브버리
resource "helm_release" "reloader" {
  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = var.reloader_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/reloader.yaml", {})
  ]
}
# 외부 비밀 저장소에서 암호 정보를 불러와서 Pod에 볼륨으로 마운트 시켜주는 라이브러리
resource "helm_release" "secrets_store_csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.secrets_store_csi_driver_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/secrets-store-csi-driver.yaml", {})
  ]
}

# Secrets Store CSI Driver에 비밀 정보를 제공해주는 AWS 라이브러리
resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = var.secrets_store_csi_driver_provider_aws_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/secrets-store-csi-driver-provider-aws.yaml", {})
  ]
}

# k8tz 설치할 네임스페이스
resource "kubernetes_namespace" "k8tz" {
  metadata {
    name = "k8tz"
  }
}

# k8tz
resource "helm_release" "k8tz" {
  name       = "k8tz"
  repository = "https://k8tz.github.io/k8tz"
  chart      = "k8tz"
  version    = var.k8tz_chart_version
  namespace  = kubernetes_namespace.k8tz.metadata[0].name

  values = [
    <<-EOT
    replicaCount: 2
    timezone: Asia/Seoul
    createNamespace: false
    namespace: null
    EOT
  ]
}


# jenkins namespace
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
}
# jenkins helm chart install
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = var.jenkins_version
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  values = [
    templatefile("${path.module}/helm-values/jenkins.yaml", {
    })
  ]
}
