# aws-eks-forge

Production-style Amazon EKS platform built with Terraform. A FastAPI application deployed on Kubernetes with managed node groups, Blue/Green deployment via ALB weighted routing, pod-level IAM (IRSA), automatic ALB provisioning via AWS Load Balancer Controller, readiness/liveness probes, and Horizontal Pod Autoscaling.

Built by **Samir Villa** as part of a hands-on DevOps/MLOps infrastructure practice series.

---

## Architecture

```
Internet
    │
    ▼
Application Load Balancer          (public subnets)
weighted routing — Blue/Green
    ├── fastapi-blue-svc  weight=100  (stable slot)
    └── fastapi-green-svc weight=0    (new version slot — 0 replicas until deploy)
         │
    ▼
EKS Cluster — Managed Node Groups  (private subnets)
    └── Namespace: api
          ├── Deployment: fastapi-blue   (v1 — active, min 2 pods)
          ├── Deployment: fastapi-green  (standby, 0 replicas)
          ├── HPA — scales blue on CPU target 70% (min 2 / max 6)
          └── ServiceAccount: fastapi-app (IRSA — pod-level IAM)
                      │
              ┌───────┴───────┐
             ECR            CloudWatch
          (Docker image)   (Container Insights — pending)
```

All worker nodes live in **private subnets**. NAT Gateway provides outbound access to ECR, EKS API and AWS services. No public IP on any node.

The **AWS Load Balancer Controller** runs inside the cluster (2 replicas, leader election) and provisions the ALB automatically from the Kubernetes Ingress resource.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| IaC | Terraform >= 1.5 (modular, one module per component) |
| Orchestration | Amazon EKS 1.31 — Managed Node Groups (EC2 t3.small) |
| Deployment Strategy | Blue/Green via ALB weighted target groups |
| Autoscaling | Horizontal Pod Autoscaler — CPU target 70%, min=2, max=6 |
| Ingress | AWS Load Balancer Controller v1.8.1 (Helm via Terraform) |
| App Framework | FastAPI + Uvicorn (Python 3.12) |
| Container Registry | Amazon ECR (scan on push, lifecycle policy) |
| Networking | VPC, public/private subnets, NAT Gateway, ALB |
| Security | IRSA (pod-level IAM), least-privilege roles, readiness + liveness probes |
| Observability | CloudWatch Container Insights (pending) |
| Remote State | S3 (versioned) + DynamoDB (state locking) |

---

## Repository Structure

```
aws-eks-forge/
├── images/
│   └── fastapi/
│       ├── main.py              # FastAPI — /, /health, /version, /items (v2 bug demo)
│       ├── Dockerfile           # python:3.12-slim, non-root workdir
│       └── requirements.txt
└── terraform/
    ├── bootstrap/               # Run once — S3 backend + DynamoDB lock table
    ├── vpc/                     # VPC, public/private subnets, IGW, NAT Gateway, route tables
    ├── eks/                     # EKS cluster 1.31, managed node group, OIDC provider
    ├── ecr/                     # ECR repository, scan on push, lifecycle policy
    ├── iam/                     # IRSA roles: alb-controller + fastapi-app (least-privilege)
    ├── alb-controller/          # AWS Load Balancer Controller via Helm + IRSA ServiceAccount
    └── k8s/                     # Namespace, ServiceAccount, Blue/Green Deployments,
                                 # Services, Ingress (weighted routing), HPA
```

---

## Remote State Design

Shared S3 backend — one bucket for all projects, isolated by key path:

```
s3://<your-tfstate-bucket>/
├── aws-eks-forge/bootstrap/terraform.tfstate
├── aws-eks-forge/vpc/terraform.tfstate
├── aws-eks-forge/eks/terraform.tfstate
├── aws-eks-forge/iam/terraform.tfstate
├── aws-eks-forge/ecr/terraform.tfstate
├── aws-eks-forge/alb-controller/terraform.tfstate
└── aws-eks-forge/k8s/terraform.tfstate
```

State locking via DynamoDB. One table shared across all projects — no collision due to key-based lock IDs.

---

## Terraform Modules

| Module | Responsibility |
|--------|---------------|
| `bootstrap` | S3 bucket + DynamoDB lock table — run once, shared across projects |
| `vpc` | VPC, public/private subnets, IGW, NAT Gateway, route tables |
| `eks` | EKS cluster 1.31, managed node group (t3.small), OIDC provider for IRSA |
| `ecr` | Private ECR repository, scan on push, lifecycle: keep last 10 tagged images |
| `iam` | IRSA role for alb-controller (kube-system SA) + fastapi-app (api SA) |
| `alb-controller` | Helm release aws-load-balancer-controller v1.8.1 + IRSA ServiceAccount |
| `k8s` | Blue/Green Deployments, ClusterIP Services, ALB Ingress, HPA |

---

## Blue/Green Deployment

Traffic is controlled via ALB weighted routing annotations on the Ingress. Green starts at 0 replicas and only scales up during a deploy.

### Key variables (`terraform/k8s/`)

| Variable | Default | Description |
|----------|---------|-------------|
| `image_tag_blue` | `v1` | Image tag for stable slot |
| `image_tag_green` | `v1` | Image tag for new version slot |
| `blue_weight` | `100` | % traffic to blue |
| `green_weight` | `0` | % traffic to green |
| `blue_replicas` | `2` | Pods in blue slot |
| `green_replicas` | `0` | Pods in green slot (0 = standby) |

### Deploy new version

```bash
# 1. Scale up green with new image, no traffic yet
terraform apply -auto-approve -var="image_tag_green=v2" -var="green_replicas=2"

# 2. Validate green pods are Ready and healthy
kubectl get pods -n api -l slot=green

# 3. Switch traffic to green
terraform apply -auto-approve -var="image_tag_green=v2" -var="green_replicas=2" -var="blue_weight=0" -var="green_weight=100"
```

### Rollback

```bash
# Option A — Terraform (restore blue, instant)
terraform apply -auto-approve -var="image_tag_green=v2" -var="green_replicas=0" -var="blue_weight=100" -var="green_weight=0"

# Option B — kubectl rollout undo (no Terraform needed)
kubectl rollout undo deployment/fastapi-blue -n api

# Option C — AWS Console → EC2 → Load Balancers → Listener Rules → adjust weights
```

---

## Deployment

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Docker
- kubectl + `aws eks update-kubeconfig`

### 1. Bootstrap (run once — shared across projects)

```bash
cd terraform/bootstrap && terraform init && terraform apply
```

> Skip if already created by another project in the same AWS account.

### 2. Apply modules in order

```bash
cd terraform/vpc           && terraform init && terraform apply
cd terraform/eks           && terraform init && terraform apply
cd terraform/iam           && terraform init && terraform apply
cd terraform/ecr           && terraform init && terraform apply
cd terraform/alb-controller && terraform init && terraform apply
cd terraform/k8s           && terraform init && terraform apply
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-forge-cluster
```

### 4. Build and push image

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ecr-url>
docker build -t eks-forge-fastapi:v1 images/fastapi/
docker tag eks-forge-fastapi:v1 <ecr-url>:v1
docker push <ecr-url>:v1
```

### 5. Verify

```bash
kubectl get pods -n api
kubectl get ingress -n api
curl http://<alb-dns>/health
```

---

## Application Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Pod identity — version, pod name, node, slot, message |
| `GET /health` | Readiness check — used by probes and ALB health check |
| `GET /version` | Version + deployment slot |
| `GET /docs` | Swagger UI (FastAPI auto-generated) |

Each response includes `pod` and `node` fields (injected via Kubernetes Downward API) so you can identify exactly which pod and node served the request.

---

## Architecture Decisions

- **Managed Node Groups over Fargate** — more representative of real-world EKS usage; direct EC2 control for node-level tuning.
- **IRSA over node-level IAM** — pod-level identity is best practice: compromising one pod does not expose credentials of other workloads on the same node.
- **Blue/Green over rolling update** — zero-downtime deploys with instant rollback. Green slot stays at 0 replicas until a deploy is in progress — no idle resource waste.
- **Readiness + liveness probes** — pods only receive traffic when `/health` returns 200. Guarantees Blue/Green switch safety and HA under pod failures.
- **AWS Load Balancer Controller** — provisions ALB natively from Kubernetes Ingress. No manual ALB management. 2 replicas with leader election for HA.
- **Terraform helm + kubernetes providers** — keeps all infrastructure (cloud and K8s layer) in a single IaC codebase.
- **NAT Gateway required** — worker nodes in private subnets need outbound access for EKS node bootstrapping and ECR image pulls.
- **Shared S3 backend** — one bucket and one DynamoDB table serve all projects, isolated by key path.

---

## Estimated Lab Cost

| Resource | Cost/hour |
|---------|-----------|
| EKS Control Plane | $0.10/hr |
| EC2 t3.small x2 (node group) | ~$0.042/hr |
| NAT Gateway | ~$0.045/hr |
| ALB | ~$0.008/hr |
| **Total** | **~$0.20/hr** |

> Destroy after the demo — EKS control plane charges even with no workloads running.
> Destroy order: `k8s` → `alb-controller` → `eks` → `vpc`. Keep `bootstrap`, `ecr` and `iam`.

---

## Related Projects

| Project | Description |
|---------|-------------|
| [aws-infra-forge](https://github.com/kratosvil/aws-infra-forge) | Foundation VPC + EC2 + RDS + S3 on AWS with Terraform |
| [aws-cloud-forge-tf](https://github.com/kratosvil/aws-cloud-forge-tf) | Multi-tier cloud infrastructure: ALB + ECS Fargate + RDS + ElastiCache |
| [aws-ai-forge](https://github.com/kratosvil/aws-ai-forge) | RAG platform on AWS — Bedrock Knowledge Bases + OpenSearch Serverless |
