module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    socks_shop_nodes = {
      desired_size   = var.desired_capacity
      min_size       = var.min_capacity
      max_size       = var.max_capacity
      instance_types = [var.node_instance_type]
    }
  }

  enable_cluster_creator_admin_permissions = true

  # Ensure VPC is created before EKS
  depends_on = [
    module.vpc
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.7.1"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_dns_hostnames   = true
}

# --- EKS Cluster Data ---
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name

  depends_on = [
    module.eks
  ]
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name

  depends_on = [
    module.eks
  ]
}

# OIDC Provider
data "aws_iam_openid_connect_provider" "oidc" {
  arn = module.eks.oidc_provider_arn

  depends_on = [
    module.eks
  ]
}

# --- ALB Controller IAM Policy ---
resource "aws_iam_policy" "alb_ingress" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for ALB Ingress Controller"
  policy      = file("${path.module}/iam_policy.json")
}

# --- ALB Controller IAM Role ---
resource "aws_iam_role" "alb_ingress" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  depends_on = [
    data.aws_iam_openid_connect_provider.oidc
  ]
}

# --- Attach Policy to Role ---
resource "aws_iam_role_policy_attachment" "alb_attach" {
  role       = aws_iam_role.alb_ingress.name
  policy_arn = aws_iam_policy.alb_ingress.arn

  depends_on = [
    aws_iam_role.alb_ingress,
    aws_iam_policy.alb_ingress
  ]
}

# --- ServiceAccount for ALB Controller ---
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_ingress.arn
    }
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.alb_attach
  ]
}

# --- Helm Release for ALB Controller ---
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = kubernetes_service_account.alb_controller.metadata[0].name
    }
  ]

  depends_on = [
    module.eks,
    kubernetes_service_account.alb_controller
  ]
}
