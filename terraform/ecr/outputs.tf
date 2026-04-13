output "repository_url" {
  description = "ECR repository URL — used to tag and push images"
  value       = aws_ecr_repository.fastapi.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.fastapi.arn
}

output "registry_id" {
  description = "AWS account ID (ECR registry ID)"
  value       = aws_ecr_repository.fastapi.registry_id
}
