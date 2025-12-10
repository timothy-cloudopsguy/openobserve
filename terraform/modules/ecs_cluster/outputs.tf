output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}


output "execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "execution_role_name" {
  description = "Name of the ECS task execution IAM role"
  value       = aws_iam_role.ecs_execution_role.name
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge IAM role for ECS"
  value       = aws_iam_role.eventbridge_ecs_role.arn
}

output "eventbridge_role_name" {
  description = "Name of the EventBridge IAM role for ECS"
  value       = aws_iam_role.eventbridge_ecs_role.name
}

output "service_discovery_namespace_id" {
  description = "ID of the Service Discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.internal.id
}