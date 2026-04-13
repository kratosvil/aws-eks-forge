output "alb_controller_role_arn" {
  description = "ARN of the IRSA role for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "fastapi_app_role_arn" {
  description = "ARN of the IRSA role for fastapi-app pod"
  value       = aws_iam_role.fastapi_app.arn
}
