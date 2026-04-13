output "ingress_name" {
  description = "Name of the Ingress resource"
  value       = kubernetes_ingress_v1.fastapi.metadata[0].name
}

output "blue_deployment" {
  description = "Blue deployment name and image"
  value       = "${kubernetes_deployment.blue.metadata[0].name} → ${local.image_base}:${var.image_tag_blue}"
}

output "green_deployment" {
  description = "Green deployment name and image"
  value       = "${kubernetes_deployment.green.metadata[0].name} → ${local.image_base}:${var.image_tag_green}"
}

output "traffic_weights" {
  description = "Current traffic split"
  value       = "blue=${var.blue_weight}% / green=${var.green_weight}%"
}
