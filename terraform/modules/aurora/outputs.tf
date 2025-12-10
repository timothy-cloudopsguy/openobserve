output "cluster_arn" {
  description = "ARN of the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.aurora_postgres.arn
}

output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.aurora_postgres.endpoint
}

output "cluster_reader_endpoint" {
  description = "Reader endpoint for the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.aurora_postgres.reader_endpoint
}

output "cluster_port" {
  description = "Port number for the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.aurora_postgres.port
}

output "cluster_identifier" {
  description = "Identifier of the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.aurora_postgres.cluster_identifier
}

output "database_name" {
  description = "Name of the default database"
  value       = aws_rds_cluster.aurora_postgres.database_name
}

output "master_username" {
  description = "Master username for the database"
  value       = aws_rds_cluster.aurora_postgres.master_username
}

output "master_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing master credentials"
  value       = aws_rds_cluster.aurora_postgres.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}

output "security_group_ssm_parameter" {
  description = "SSM parameter path containing the Aurora security group ID"
  value       = aws_ssm_parameter.aurora_security_group_id.name
}

output "global_cluster_id" {
  description = "ID of the Aurora Global Cluster (when enabled)"
  value       = var.aurora_config.global_enabled ? aws_rds_global_cluster.aurora_global[0].id : null
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Cluster (when enabled)"
  value       = var.aurora_config.global_enabled ? aws_rds_global_cluster.aurora_global[0].arn : null
}

output "reader_instance_identifiers" {
  description = "Identifiers of the Aurora reader instances"
  value       = aws_rds_cluster_instance.aurora_readers[*].identifier
}

output "reader_endpoints" {
  description = "Endpoints of the Aurora reader instances"
  value       = [for instance in aws_rds_cluster_instance.aurora_readers : instance.endpoint]
}

output "route53_writer_record" {
  description = "Route53 DNS name for Aurora writer endpoint"
  value       = "${lower(var.app_name)}-rds-rw.${var.route53_domain_name}"
}

output "route53_reader_record" {
  description = "Route53 DNS name for Aurora reader endpoints"
  value       = "${lower(var.app_name)}-rds-ro.${var.route53_domain_name}"
}
