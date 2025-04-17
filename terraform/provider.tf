# 요구되는 테라폼 제공자 목록
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.56.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.4"
    }
  }
}

# 테라폼 백엔드 설정
terraform {
  backend "s3" {
    region         = "ap-northeast-2"
    bucket         = "seungdobae-terraform-state"
    key            = "eks-sdp/terraform.tfstate"
    dynamodb_table = "eks-sdp-terraform-lock"
    encrypt        = true
  }
}

# AWS 제공자 설정
provider "aws" {
  default_tags {
    tags = local.tags
  }
}
provider "aws" {
  alias = "us_east_1"

  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}

# Kubernetes 제공자 설정
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Helm 제공자 설정
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
  debug = true
}

# Kubectl 제공자 설정
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}