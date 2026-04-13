output "helm_release_status" {
  description = "Status of the ALB controller Helm release"
  value       = helm_release.alb_controller.status
}

output "helm_release_version" {
  description = "Chart version deployed"
  value       = helm_release.alb_controller.version
}
