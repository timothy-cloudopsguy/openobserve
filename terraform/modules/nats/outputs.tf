output "service_arn" {
  value = aws_ecs_service.nats.arn
}

output "nats_url" {
  description = "NATS connection URL using service discovery"
  value       = "nats://${var.app_name}-nats.${var.app_name}.local:4222"
}

output "nats_monitoring_url" {
  description = "NATS monitoring URL using service discovery"
  value       = "http://${var.app_name}-nats.${var.app_name}.local:8222"
}