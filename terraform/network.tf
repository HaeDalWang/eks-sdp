# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = local.project
  cidr = var.vpc_cidr

  azs              = data.aws_availability_zones.azs.names
  public_subnets   = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnets  = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 10)]

  default_security_group_egress = [
    {
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]

  enable_nat_gateway = true
  single_nat_gateway = true

  # 외부 접근용 ALB/NLB를 생성할 서브넷에요구되는 태그
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # VPC 내부용 ALB/NLB를 생성할 서브넷에 요구되는 태그
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter가 노드를 생성할 서브넷에 요구되는 태그
    "karpenter.sh/discovery" = local.project
  }

  secondary_cidr_blocks = [
    "10.122.0.0/16"  # 원하는 보조 CIDR 블록을 추가 작성
  ]
}

## EKS IP 부족 시 해결하기 위한 방법
# EKS 클러스터에 연결할 새로운 범위에 VPC 서브넷
resource "aws_subnet" "new_private_subnet_a" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.240.150.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.project
  }
}

# 새로운 서브넷에 대한 라우팅 테이블을 업데이트
resource "aws_route_table_association" "new_private_subnet_route" {
  subnet_id      = aws_subnet.new_private_subnet_a.id
  route_table_id = module.vpc.private_route_table_ids[0] # VPC 모듈에서 반환된 첫 번째 라우팅 테이블 사용
}


# 새로운 세컨더리 VPC 범위에 서브넷
resource "aws_subnet" "new_private_subnet_c" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.122.1.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.project
  }
}

# 새로운 서브넷에 대한 라우팅 테이블을 업데이트
resource "aws_route_table_association" "new_private_subnet_route_c" {
  subnet_id      = aws_subnet.new_private_subnet_c.id
  route_table_id = module.vpc.private_route_table_ids[0] # VPC 모듈에서 반환된 첫 번째 라우팅 테이블 사용
}