
output "aurora_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL cluster"
  value       = module.aurora.cluster_arn
}

output "aurora_cluster_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster"
  value       = module.aurora.cluster_endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Reader endpoint for the Aurora PostgreSQL cluster"
  value       = module.aurora.cluster_reader_endpoint
}

output "aurora_cluster_port" {
  description = "Port number for the Aurora PostgreSQL cluster"
  value       = module.aurora.cluster_port
}

output "aurora_cluster_identifier" {
  description = "Identifier of the Aurora PostgreSQL cluster"
  value       = module.aurora.cluster_identifier
}

output "aurora_database_name" {
  description = "Name of the default database"
  value       = module.aurora.database_name
}

output "aurora_master_username" {
  description = "Master username for the database"
  value       = module.aurora.master_username
}

output "aurora_master_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Aurora master credentials"
  value       = module.aurora.master_credentials_secret_arn
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group"
  value       = module.aurora.security_group_id
}

output "aurora_security_group_ssm_parameter" {
  description = "SSM parameter path containing the Aurora security group ID"
  value       = module.aurora.security_group_ssm_parameter
}

output "aurora_global_cluster_id" {
  description = "ID of the Aurora Global Cluster (when enabled)"
  value       = module.aurora.global_cluster_id
}

output "aurora_global_cluster_arn" {
  description = "ARN of the Aurora Global Cluster (when enabled)"
  value       = module.aurora.global_cluster_arn
}

output "aurora_reader_instance_identifiers" {
  description = "Identifiers of the Aurora reader instances"
  value       = module.aurora.reader_instance_identifiers
}

output "aurora_reader_endpoints" {
  description = "Endpoints of the Aurora reader instances"
  value       = module.aurora.reader_endpoints
}

# output "database_service_accounts" {
#   description = "Database service account configurations"
#   value = {
#     for name, account in module.database_service_accounts : name => {
#       ssm_parameter_name = account.ssm_parameter_name
#       lambda_function    = account.lambda_function_name
#       service_account    = account.service_account_name
#     }
#   }
# }
