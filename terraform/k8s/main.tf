# -------------------------------------------------------
# Remote State — IAM + VPC outputs
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

data "terraform_remote_state" "ecr" {
  backend = "s3"
  config = {
    bucket = "terraform-state-kratosvil"
    key    = "aws-eks-forge/ecr/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  image_base = data.terraform_remote_state.ecr.outputs.repository_url
}

# -------------------------------------------------------
# Namespace
# -------------------------------------------------------

resource "kubernetes_namespace" "api" {
  metadata {
    name = "api"
    labels = {
      project = var.project
    }
  }
}

# -------------------------------------------------------
# ServiceAccount — IRSA annotation for fastapi-app
# -------------------------------------------------------

resource "kubernetes_service_account" "fastapi" {
  metadata {
    name      = "fastapi-app"
    namespace = kubernetes_namespace.api.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.iam.outputs.fastapi_app_role_arn
    }
  }
}

# -------------------------------------------------------
# Deployment — Blue (stable slot)
# -------------------------------------------------------

resource "kubernetes_deployment" "blue" {
  metadata {
    name      = "fastapi-blue"
    namespace = kubernetes_namespace.api.metadata[0].name
    labels = {
      app  = "fastapi"
      slot = "blue"
    }
  }

  spec {
    replicas = var.blue_replicas

    selector {
      match_labels = {
        app  = "fastapi"
        slot = "blue"
      }
    }

    template {
      metadata {
        labels = {
          app  = "fastapi"
          slot = "blue"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fastapi.metadata[0].name

        container {
          name  = "fastapi"
          image = "${local.image_base}:${var.image_tag_blue}"

          port {
            container_port = 8000
          }

          env {
            name  = "APP_VERSION"
            value = var.image_tag_blue
          }

          env {
            name  = "DEPLOYMENT_SLOT"
            value = "blue"
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# -------------------------------------------------------
# Deployment — Green (new version slot)
# -------------------------------------------------------

resource "kubernetes_deployment" "green" {
  metadata {
    name      = "fastapi-green"
    namespace = kubernetes_namespace.api.metadata[0].name
    labels = {
      app  = "fastapi"
      slot = "green"
    }
  }

  spec {
    replicas = var.green_replicas

    selector {
      match_labels = {
        app  = "fastapi"
        slot = "green"
      }
    }

    template {
      metadata {
        labels = {
          app  = "fastapi"
          slot = "green"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fastapi.metadata[0].name

        container {
          name  = "fastapi"
          image = "${local.image_base}:${var.image_tag_green}"

          port {
            container_port = 8000
          }

          env {
            name  = "APP_VERSION"
            value = var.image_tag_green
          }

          env {
            name  = "DEPLOYMENT_SLOT"
            value = "green"
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# -------------------------------------------------------
# Services — one per slot
# -------------------------------------------------------

resource "kubernetes_service" "blue" {
  metadata {
    name      = "fastapi-blue-svc"
    namespace = kubernetes_namespace.api.metadata[0].name
  }

  spec {
    selector = {
      app  = "fastapi"
      slot = "blue"
    }

    port {
      port        = 80
      target_port = 8000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service" "green" {
  metadata {
    name      = "fastapi-green-svc"
    namespace = kubernetes_namespace.api.metadata[0].name
  }

  spec {
    selector = {
      app  = "fastapi"
      slot = "green"
    }

    port {
      port        = 80
      target_port = 8000
    }

    type = "ClusterIP"
  }
}

# -------------------------------------------------------
# Ingress — ALB with weighted Blue/Green routing
# -------------------------------------------------------

resource "kubernetes_ingress_v1" "fastapi" {
  metadata {
    name      = "fastapi-ingress"
    namespace = kubernetes_namespace.api.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                        = "alb"
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/subnets"                  = join(",", data.terraform_remote_state.vpc.outputs.public_subnet_ids)
      "alb.ingress.kubernetes.io/healthcheck-path"         = "/health"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "15"
      "alb.ingress.kubernetes.io/healthy-threshold-count"  = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count" = "3"
      "alb.ingress.kubernetes.io/actions.weighted-routing" = jsonencode({
        type = "forward"
        forwardConfig = {
          targetGroups = [
            {
              serviceName = kubernetes_service.blue.metadata[0].name
              servicePort = "80"
              weight      = var.blue_weight
            },
            {
              serviceName = kubernetes_service.green.metadata[0].name
              servicePort = "80"
              weight      = var.green_weight
            }
          ]
        }
      })
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "weighted-routing"
              port {
                name = "use-annotation"
              }
            }
          }
        }
      }
    }
  }
}

# -------------------------------------------------------
# HPA — autoscaling sobre blue (slot activo)
# -------------------------------------------------------

resource "kubernetes_horizontal_pod_autoscaler_v2" "blue" {
  metadata {
    name      = "fastapi-blue-hpa"
    namespace = kubernetes_namespace.api.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.blue.metadata[0].name
    }

    min_replicas = 2
    max_replicas = 6

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}
