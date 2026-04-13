# -------------------------------------------------------
# Remote State — read IAM and VPC outputs
# -------------------------------------------------------

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "terraform-state-kratosvil"
    key    = "aws-eks-forge/iam/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "terraform-state-kratosvil"
    key    = "aws-eks-forge/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# -------------------------------------------------------
# Kubernetes ServiceAccount — annotated with IRSA role
# -------------------------------------------------------

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.iam.outputs.alb_controller_role_arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
  }
}

# -------------------------------------------------------
# Helm Release — AWS Load Balancer Controller
# -------------------------------------------------------

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.eks.outputs.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.vpc.outputs.vpc_id
  }

  set {
    name  = "replicaCount"
    value = "2"
  }

  depends_on = [kubernetes_service_account.alb_controller]
}
