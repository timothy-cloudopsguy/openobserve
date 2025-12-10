# Data sources to pull VPC and subnet information from iac-core stack
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.iac_core_stack_name}/vpc/${lower(var.env_name)}/id"
}

data "aws_ssm_parameter" "vpc_cidr" {
  name = "/${var.iac_core_stack_name}/vpc/${lower(var.env_name)}/cidr"
}

data "aws_subnets" "persistence" {
  filter {
    name   = "tag:Type"
    values = ["persistence"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_ssm_parameter.vpc_id.value]
  }
}

locals {
  suffix = lower(random_id.suffix.hex)
}

resource "random_id" "suffix" {
  byte_length = 2
}

# Security group for Aurora cluster
resource "aws_security_group" "aurora" {
  name        = "${var.app_name}-aurora-postgres-${local.suffix}"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  # Allow PostgreSQL access from VPC
  ingress {
    description = "PostgreSQL access from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_ssm_parameter.vpc_cidr.value]
  }

  tags = {
    Name        = "${var.app_name}-aurora-postgres-${local.suffix}"
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# Store security group ID in SSM Parameter Store
resource "aws_ssm_parameter" "aurora_security_group_id" {
  name        = "/${var.app_name}/aurora-postgres/security-group-id"
  description = "Security group ID for Aurora PostgreSQL cluster"
  type        = "String"
  value       = aws_security_group.aurora.id

  tags = {
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# Aurora Global Cluster (when enabled)
resource "aws_rds_global_cluster" "aurora_global" {
  count                     = var.aurora_config.global_enabled ? 1 : 0
  global_cluster_identifier = "${lower(var.app_name)}-aurora-global-${local.suffix}"
  engine                    = "aurora-postgresql"
  engine_version            = "16.9"
  database_name             = var.aurora_config.db_name
  deletion_protection       = true


  tags = {
    Name        = "${var.app_name}-aurora-global-${local.suffix}"
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# Aurora PostgreSQL Serverless v2 Cluster
resource "aws_rds_cluster" "aurora_postgres" {
  cluster_identifier      = "${lower(var.app_name)}-aurora-postgres-${local.suffix}"
  engine                  = "aurora-postgresql"
  engine_version          = "16.9"
  database_name           = var.aurora_config.db_name
  master_username         = var.aurora_config.master_username
  manage_master_user_password = true
  global_cluster_identifier = var.aurora_config.global_enabled ? aws_rds_global_cluster.aurora_global[0].id : null

  # Serverless v2 configuration
  serverlessv2_scaling_configuration {
    max_capacity = var.aurora_config.max_acu
    min_capacity = var.aurora_config.min_acu
    seconds_until_auto_pause = var.aurora_config.min_acu < 0.5 ? var.aurora_config.seconds_until_auto_pause : null
  }

  # IO optimized storage
  storage_type = "aurora-iopt1"

  # Networking
  vpc_security_group_ids = [aws_security_group.aurora.id]
  db_subnet_group_name   = aws_db_subnet_group.aurora.name

  # Backup configuration
  backup_retention_period = var.aurora_config.backup_retention_period
  preferred_backup_window = var.aurora_config.preferred_backup_window

  # Maintenance
  preferred_maintenance_window = var.aurora_config.preferred_maintenance_window

  # Enable deletion protection
  deletion_protection = var.aurora_config.deletion_protection

  # Skip final snapshot for development
  skip_final_snapshot = true

  tags = {
    Name        = "${var.app_name}-aurora-postgres-${local.suffix}"
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# Multi-AZ Read Replicas for high availability
resource "aws_rds_cluster_instance" "aurora_readers" {
  count              = var.aurora_config.reader_count
  identifier         = "${lower(var.app_name)}-aurora-reader-${count.index + 1}-${local.suffix}"
  cluster_identifier = aws_rds_cluster.aurora_postgres.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora_postgres.engine
  engine_version     = aws_rds_cluster.aurora_postgres.engine_version

  tags = {
    Name        = "${var.app_name}-aurora-reader-${count.index + 1}-${local.suffix}"
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# DB subnet group for persistence subnets
resource "aws_db_subnet_group" "aurora" {
  name       = "${lower(var.app_name)}-aurora-postgres-${local.suffix}"
  subnet_ids = data.aws_subnets.persistence.ids

  tags = {
    Name        = "${var.app_name}-aurora-postgres-${local.suffix}"
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# Get Route53 zone information
data "aws_route53_zone" "selected" {
  name = var.route53_domain_name
}

# Resolve writer endpoint to IP address
data "external" "resolve_writer_endpoint" {
  depends_on = [
    aws_rds_cluster.aurora_postgres,
    aws_rds_cluster_instance.aurora_readers
  ]

  program = ["bash", "-c", "echo '{\"ip\": \"'$(dig +short ${aws_rds_cluster.aurora_postgres.endpoint} | head -1)'\"}'"]
}

# Resolve reader endpoints to IP addresses
data "external" "resolve_reader_endpoints" {
  count   = var.aurora_config.reader_count
  depends_on = [
    aws_rds_cluster.aurora_postgres,
    aws_rds_cluster_instance.aurora_readers
  ]

  program = ["bash", "-c", "echo '{\"ip\": \"'$(dig +short ${aws_rds_cluster_instance.aurora_readers[count.index].endpoint} | head -1)'\"}'"]
}

# create a CNAME record for the Aurora writer endpoint
resource "aws_route53_record" "aurora_writer" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${lower(var.app_name)}-rds-rw.${var.route53_domain_name}"
  type    = "CNAME"
  ttl     = var.route53_ttl
  records = [aws_rds_cluster.aurora_postgres.endpoint]
}

# create a CNAME record for the Aurora reader endpoint
resource "aws_route53_record" "aurora_reader" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${lower(var.app_name)}-rds-ro.${var.route53_domain_name}"
  type    = "CNAME"
  ttl     = var.route53_ttl
  records = [aws_rds_cluster_instance.aurora_readers[0].endpoint]
}

resource "aws_ssm_parameter" "aurora_port" {
  name        = "/${var.app_name}/aurora/port"
  description = "Port for the Aurora PostgreSQL cluster"
  type        = "String"
  value       = aws_rds_cluster.aurora_postgres.port

  tags = {
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

resource "aws_ssm_parameter" "master_secret_arn" {
  name        = "/${var.app_name}/aurora/master_secret_arn"
  description = "ARN of the Secrets Manager secret containing Aurora master credentials"
  type        = "String"
  value       = aws_rds_cluster.aurora_postgres.master_user_secret[0].secret_arn

  tags = {
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}