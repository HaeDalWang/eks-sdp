# EKS 클러스터
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.15.0"

  cluster_name    = local.project
  cluster_version = var.eks_cluster_version

  # EKS Add-on
  cluster_addons = {
    coredns = {
      # 클러스터 버전에 맞게 최신 버전을 동적으로 불러와서 적용
      most_recent = true
      configuration_values = jsonencode({
        # Karpenter가 실행되려면 CoreDNS가 필수 구성요소기 때문에 Fargate에 배포
        computeType = "Fargate"
        resources = {
          limits = {
            cpu    = "0.25"
            memory = "256M"
          }
          requests = {
            cpu    = "0.25"
            memory = "256M"
          }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id = module.vpc.vpc_id
  # 노드그룹을 사용할 경우 노드가 생성되는 서브넷
  subnet_ids = module.vpc.private_subnets
  # 컨트롤 플레인으로 연결된 ENI를 생성할 서브넷
  control_plane_subnet_ids = module.vpc.intra_subnets

  # 클러스터를 생성한 IAM 객체에서 쿠버네티스 어드민 권한 할당
  enable_cluster_creator_admin_permissions = true

  # 노드그룹을 사용하지 않기 때문에 노드 그룹용 보인그룹 미생성
  create_node_security_group = false

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access = true

  fargate_profiles = {
    # Karpenter를 Fargate에 실행
    karpenter = {
      selectors = [
        {
          namespace = "karpenter"
        }
      ]
    }
    # CoreDNS를 Fargate에 실행
    coredns = {
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        }
      ]
    }
  }

  # 로깅 비활성화 - 변수처리
  cluster_enabled_log_types = []
}

# Karpenter 구성에 필요한 AWS 리소스 생성
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.15.0"

  cluster_name                  = module.eks.cluster_name
  node_iam_role_name            = "${module.eks.cluster_name}-node-role"
  node_iam_role_use_name_prefix = false

  # Karpenter에 부여할 IAM 역할 생성
  enable_irsa            = true
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  # Karpenter가 생성할 노드에 부여할 역할에 기본 정책 이외에 추가할 IAM 정책
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

# Karpenter를 배포할 네임 스페이스
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

# Karpenter
resource "helm_release" "karpenter-crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart      = "karpenter-crd"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace.karpenter.metadata[0].name
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace.karpenter.metadata[0].name

  skip_crds = true

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
      featureGates:
        spotToSpotConsolidation: true
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    serviceMonitor:
      enabled: true
    EOT
  ]
}

## NodeClass
resource "kubectl_manifest" "karpenter_basic_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: basic
    spec:
      amiFamily: AL2023
      amiSelectorTerms:
      # - id: "${var.eks_node_ami_id}"
      - alias: al2023@v20250410
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
      - id: ${module.eks.cluster_primary_security_group_id}
      blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 20Gi
          volumeType: gp3
          encrypted: true
      metadataOptions:
        httpPutResponseHopLimit: 2
      tags:
        ${jsonencode(local.tags)}
    YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# ## Node Pool
resource "kubectl_manifest" "karpenter_basic_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: basic
    spec:
      weight: 50
      template:
        spec:
          expireAfter: 720h
          requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          - key: node.kubernetes.io/instance-type
            operator: In
            values: [
              "t3.medium", "t3a.medium",
              "c5.large", "c5a.large", "c6a.large",
              "c5.xlarge", "c5a.xlarge", "c6a.xlarge"
            ]
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1
            kind: EC2NodeClass
            name: "basic"
            group: karpenter.k8s.aws
      limits:
        cpu: 3200
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized 
        consolidateAfter: 30s
  YAML

  depends_on = [
    kubectl_manifest.karpenter_basic_node_class
  ]
}

# EBS CSI 드라이버를 사용하는 스토리지 클래스
resource "kubernetes_storage_class" "ebs_sc" {
  # EBS CSI 드라이버가 EKS Addon을 통해서 생성될 경우
  count = lookup(module.eks.cluster_addons, "aws-ebs-csi-driver", null) != null ? 1 : 0

  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# 기본값으로 생성된 스토리지 클래스 해제
resource "kubernetes_annotations" "default_storageclass" {
  count = lookup(module.eks.cluster_addons, "aws-ebs-csi-driver", null) != null ? 1 : 0

  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = "true"

  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  depends_on = [
    kubernetes_storage_class.ebs_sc
  ]
}

/* 필수 라이브러리 */
# Metrics Server
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"
}

# ExternalDNS에 부여할 IAM 역할 및 Pod Identity Association
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "1.2.1"

  name = "external-dns"

  attach_external_dns_policy = true
  external_dns_hosted_zone_arns = [
    data.aws_route53_zone.this.arn
  ]

  associations = {
    (module.eks.cluster_name) = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
      tags = {
        app = "external-dns"
      }
    }
  }
}

# ExternalDNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: ${module.external_dns_pod_identity.iam_role_arn}
    txtOwnerId: ${module.eks.cluster_name}
    policy: sync
    extraArgs:
    - --annotation-filter=external-dns.alpha.kubernetes.io/exclude notin (true)
    EOT
  ]
}

# AWS Load Balancer Controller에 부여할 IAM 역할 및 Pod Identity Association
module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "1.2.1"

  name = "aws-load-balancer-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    (module.eks.cluster_name) = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      tags = {
        app = "aws-load-balancer-controller"
      }
    }
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    clusterName: ${module.eks.cluster_name}
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: ${module.aws_load_balancer_controller_pod_identity.iam_role_arn}
    EOT
  ]
}