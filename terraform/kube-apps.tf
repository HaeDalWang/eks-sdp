# Ingress NGINX를 설치할 네임스페이스
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

# 이미 존재하는 ACM 인증서가 있는지 확인
data "aws_acm_certificate" "service_domain" {
  domain   = "${local.service_domain_name}"
  statuses = ["ISSUED"]
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
