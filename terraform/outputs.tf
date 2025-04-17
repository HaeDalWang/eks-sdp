output "network" {
  description = "VPC 및 네트워크 관련 정보"
  value = {
    vpc_id                                = module.vpc.vpc_id
    eks_cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  }
}