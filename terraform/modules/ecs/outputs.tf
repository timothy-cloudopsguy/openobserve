output "service_arn" {
  description = "ARN of the ECS service (if deployed as service)"
  value       = var.service_config.deploy_as_service ? aws_ecs_service.this[0].id : null
}

output "service_name" {
  description = "Name of the ECS service (if deployed as service)"
  value       = var.service_config.deploy_as_service ? aws_ecs_service.this[0].name : null
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Family name of the ECS task definition"
  value       = aws_ecs_task_definition.this.family
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for this service"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for this service"
  value       = aws_cloudwatch_log_group.this.arn
}

output "scheduled_rule_name" {
  description = "Name of the EventBridge rule for scheduled execution (if applicable)"
  value       = (!var.service_config.deploy_as_service && var.service_config.schedule != null) ? aws_cloudwatch_event_rule.scheduled[0].name : null
}

output "scheduled_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled execution (if applicable)"
  value       = (!var.service_config.deploy_as_service && var.service_config.schedule != null) ? aws_cloudwatch_event_rule.scheduled[0].arn : null
}

output "ssm_parameters" {
  description = "Map of SSM parameters created for service secrets"
  value = {
    for k, v in aws_ssm_parameter.service_secrets : k => {
      name = v.name
      arn  = v.arn
    }
  }
}

output "secrets_manager_secrets" {
  description = "Map of Secrets Manager secrets created for service secrets"
  value = {
    for secret_name, secret in aws_secretsmanager_secret.service_secrets : secret_name => {
      name = secret.name
      arn  = secret.arn
    }
  }
}
