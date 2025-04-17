# AWS 지역 정보 불러오기
data "aws_region" "current" {}

# 현재 설정된 AWS 리전에 있는 가용영역 정보 불러오기
data "aws_availability_zones" "azs" {}

# 현재 Terraform을 실행하는 IAM 객체
data "aws_caller_identity" "current" {}

# Route53 호스트존
data "aws_route53_zone" "this" {
  name = "${var.domain_name}."
}
# us-east-1 전용 권한 ECR 레포용
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.us_east_1
}
# EKS 클러스터 인증 토큰
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# # 암호 정보가 저장된 Secrets
# data "aws_secretsmanager_secret_version" "this" {
#   secret_id = local.project
# }
