# aws-eks-forge

Production-style Amazon EKS platform built with Terraform. A FastAPI application deployed on Kubernetes with managed node groups, pod-level IAM (IRSA), automatic ALB provisioning via AWS Load Balancer Controller, and Horizontal Pod Autoscaling.

Built by **Samir Villa** as part of a hands-on DevOps/MLOps infrastructure practice series.

---

## Architecture

```
Internet
    │
    ▼
AWS Load Balancer Controller
(provisions ALB automatically from K8s Ingress resource)
    │
    ▼
Application Load Balancer          (public subnets)
    │
    ▼
EKS Cluster — Managed Node Groups  (private subnets)
    └── Namespace: api
          └── Deployment: fastapi-app
                ├── ReplicaSet (min 2 pods)
                ├── HPA — scales on CPU target 70%
                └── IRSA — pod-level IAM role (not node-level)
                      │
              ┌───────┴───────┐
             ECR           CloudWatch
          (Docker image)  (Container Insights)
```

All worker nodes live in **private subnets**. NAT Gateway provides outbound access to ECR, EKS API and AWS services. No public IP on any node.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| IaC | Terraform >= 1.5 (modular, one module per component) |
| Orchestration | Amazon EKS — Managed Node Groups (EC2 t3.medium) |
| Autoscaling | Horizontal Pod Autoscaler (CPU target tracking) |
| Ingress | AWS Load Balancer Controller (Helm via Terraform) |
| App Framework | FastAPI + Uvicorn (Python 3.12) |
| Container Registry | Amazon ECR (immutable tags, scan on push) |
| Networking | VPC, public/private subnets, NAT Gateway, ALB |
| Security | IRSA (pod-level IAM), least-privilege roles, SGs |
| Observability | CloudWatch Container Insights + CloudWatch Logs |
| Remote State | S3 (versioned) + DynamoDB (state locking) |

---

## Repository Structure

```
aws-eks-forge/
├── bootstrap/                   # Run once — creates S3 backend + DynamoDB lock table
│   ├── main.tf
│   └── outputs.tf
└── terraform/
    ├── backend.tf               # Remote state: S3 + DynamoDB
    ├── main.tf                  # Orchestrator — module calls only
    ├── variables.tf
    ├── outputs.tf
    └── modules/
        ├── vpc/                 # VPC, subnets, IGW, NAT Gateway, route tables, SGs
        ├── eks/                 # EKS cluster, managed node group, OIDC provider
        ├── ecr/                 # ECR repository
        ├── iam/                 # IRSA roles, node group role, cluster role
        ├── alb-controller/      # AWS Load Balancer Controller via Helm
        └── k8s/                 # K8s manifests: Deployment, Service, Ingress, HPA
```

---

## Remote State Design

This project uses a **shared S3 backend** — one bucket for all projects, isolated by key path:

```
s3://<your-tfstate-bucket>/
├── aws-eks-forge/terraform.tfstate     ← this project
├── aws-cloud-forge-tf/terraform.tfstate
└── ...
```

State locking is handled by a single DynamoDB table shared across all projects. Lock IDs include the state path, so there is no collision between projects.

The `bootstrap/` directory creates these shared resources once. All subsequent projects only need to configure their `backend.tf` with the appropriate `key`.

---

## Terraform Modules

| Module | Responsibility |
|--------|---------------|
| `vpc` | VPC, public/private subnets, IGW, NAT Gateway, route tables, security groups |
| `eks` | EKS cluster, managed node group (t3.medium), OIDC provider for IRSA |
| `ecr` | Private ECR repository, immutable tags, scan on push |
| `iam` | IRSA roles per service account, node group role, cluster role |
| `alb-controller` | AWS Load Balancer Controller via Terraform helm provider |
| `k8s` | Deployment, Service, Ingress, HPA via Terraform kubernetes provider |

---

## Deployment

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Docker

### 1. Bootstrap (run once — shared across projects)

```bash
cd bootstrap
terraform init
terraform apply
```

> Creates the shared S3 bucket and DynamoDB lock table.
> Skip if already created by another project in the same AWS account.

### 2. Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Docker Image

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ecr-url>

# Build, tag and push
docker build -t aws-eks-forge-api ./app
docker tag aws-eks-forge-api:latest <ecr-url>:latest
docker push <ecr-url>:latest
```

### 4. Verify deployment

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name aws-eks-forge-cluster

# Check pods
kubectl get pods -n api

# Get ALB endpoint
kubectl get ingress -n api
```

---

## Architecture Decisions

- **Managed Node Groups over Fargate** — more representative of real-world EKS usage; direct EC2 control for node-level tuning.
- **IRSA over node-level IAM** — pod-level identity is best practice: compromising one pod does not expose credentials of other workloads on the same node.
- **AWS Load Balancer Controller** — provisions ALB natively from Kubernetes Ingress resources. No manual ALB management.
- **Terraform helm + kubernetes providers** — keeps all infrastructure (cloud and K8s layer) in a single IaC codebase.
- **NAT Gateway required** — worker nodes in private subnets need outbound access. Unlike aws-ai-forge, VPC Endpoints alone are not sufficient for EKS node bootstrapping.
- **Shared S3 backend** — one bucket and one DynamoDB table serve all projects. Isolated by key path per project.

---

## Estimated Lab Cost

| Resource | Cost/hour |
|---------|-----------|
| EKS Control Plane | $0.10/hr |
| EC2 t3.medium x2 (node group) | ~$0.083/hr |
| NAT Gateway | ~$0.045/hr |
| ALB | ~$0.008/hr |
| **Total** | **~$0.24/hr** |

> Run `terraform destroy` after the demo. EKS control plane charges even with no workloads.
