
data "aws_organizations_organization" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ssm_parameter" "vpc_id" {
  count = local.props.vpc.create ? 0 : 1
  name = "/${local.props.iac_core_name}${title(var.environment)}/vpc/${lower(var.environment)}/id"
}

data "aws_ssm_parameter" "vpc_cidr" {
  count = local.props.vpc.create ? 0 : 1
  name = "/${local.props.iac_core_name}${title(var.environment)}/vpc/${lower(var.environment)}/cidr"
}

# Build a standard VPC
module "vpc" {
  count = local.props.vpc.create ? 1 : 0
  source     = "./modules/vpc"
  app_name   = local.app_name
  env_name   = local.env_name
  props_file = local.props_file
  vpc        = local.props.vpc
  region     = data.aws_region.current.id
  account_id = data.aws_caller_identity.current.account_id
}

locals{
  vpc_id = local.props.vpc.create ? module.vpc[0].vpc_ids[local.props.vpc.name] : data.aws_ssm_parameter.vpc_id[0].value
  vpc_cidr = local.props.vpc.create ? module.vpc[0].cidr_blocks[local.props.vpc.name] : data.aws_ssm_parameter.vpc_cidr[0].value
}

# Get app subnet IDs (assuming they exist in SSM or we need to derive them)
data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}

# Get support subnet IDs for Lambda functions and other infrastructure
data "aws_subnets" "support_subnets" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["support"]
  }
}

# Route53 hosted zone for SSL certificate validation
data "aws_route53_zone" "cert_zone" {
  name = local.props.route53.domain_name
}

# ALB information for ECS services
data "aws_ssm_parameter" "alb_arn" {
  count = local.props.alb.create ? 0 : 1
  name = "/${local.iac_core_stack_name}/alb/${lower(var.environment)}/arn"
}

data "aws_ssm_parameter" "alb_dns_name" {
  count = local.props.alb.create ? 0 : 1
  name = "/${local.iac_core_stack_name}/alb/${lower(var.environment)}/dns-name"
}

data "aws_ssm_parameter" "alb_sg_id" {
  count = local.props.alb.create ? 0 : 1
  name = "/${local.iac_core_stack_name}/alb/${lower(var.environment)}/sg-id"
}

data "aws_ssm_parameter" "alb_listener_arn" {
  count = local.props.alb.create ? 0 : 1
  name = "/${local.iac_core_stack_name}/alb/${lower(var.environment)}/listener-arn"
}


locals {
  organization_id = data.aws_organizations_organization.current.id
  aws_org_ids = distinct(concat(local.props.aws_org_ids, [local.organization_id]))
  aurora_writer = "${lower(local.app_name)}-rds-rw.${local.props.route53.domain_name}"
}

module "s3" {
  count       = local.props.s3.create ? 1 : 0
  source      = "./modules/s3"
  app_name    = local.app_name
  env_name    = local.env_name
  props_file  = local.props_file
  organization_id  = local.organization_id
  aws_org_ids = local.aws_org_ids
  region      = var.region
}

module "aurora" {
  source                       = "./modules/aurora"
  app_name                     = local.app_name
  env_name                     = local.env_name
  iac_core_stack_name          = local.iac_core_stack_name
  aurora_config                = local.aurora_config
  route53_domain_name          = local.route53_domain_name
  route53_ttl                  = local.route53_ttl
}

# Database service accounts
module "database_service_accounts" {
  for_each = { for account in local.database_service_accounts : account.name => account }

  source = "./modules/db-service-account"

  app_name                 = local.app_name
  env_name                 = local.env_name
  service_account_name     = each.value.name
  database_name            = "openobserve"
  permissions              = each.value.permissions
  tables                   = lookup(each.value, "tables", [])
  schema_permissions       = lookup(each.value, "schema_permissions", [])
  database_privileges      = lookup(each.value, "database_privileges", [])
  update_permissions       = lookup(each.value, "update_permissions", false)
  aurora_endpoint          = local.aurora_writer
  aurora_port              = module.aurora.cluster_port
  aurora_master_secret_arn = module.aurora.master_credentials_secret_arn
  ssm_parameter_name       = "/${local.app_name}/db-service-accounts/${each.value.name}"
  iac_core_stack_name      = local.iac_core_stack_name
}


# ECS Cluster Module
module "ecs_cluster" {
  source = "./modules/ecs_cluster"
  vpc_id                        = local.vpc_id
  app_name                      = local.app_name
  environment                   = var.environment
  region                        = var.region
  enable_container_insights     = local.props.ecs.enable_container_insights
  off_hours_scaling             = local.props.ecs.off_hours_scaling
}


module "nats" {
  source                         = "./modules/nats"
  aws_region                     = var.region
  app_name                       = local.app_name
  env                            = var.environment
  vpc_id                         = local.vpc_id
  cluster_arn                    = module.ecs_cluster.cluster_arn
  subnet_ids                     = data.aws_subnets.support_subnets.ids # use public_subnets if you want to access NATS server from outside (for monitoring etc.)
  image                          = "public.ecr.aws/docker/library/nats:2.11.11-alpine"
  desired_count                  = local.props.nats.desired_count
  execution_role_arn             = module.ecs_cluster.execution_role_arn
  service_discovery_namespace_id = module.ecs_cluster.service_discovery_namespace_id
  depends_on                     = [module.ecs_cluster]
}

# Build a public ALB if 
module "alb" {
  count = local.props.alb.create ? 1 : 0
  source               = "./modules/alb"
  app_name             = local.app_name
  env_name             = var.environment
  vpc_id               = local.vpc_id
  public_subnet_ids    = data.aws_subnets.public_subnets.ids
  region               = data.aws_region.current.id
  account_id           = data.aws_caller_identity.current.account_id
  route53_hosted_zones = local.props.route53
}

locals {
  alb_arn = local.props.alb.create ? module.alb[0].alb_arn : data.aws_ssm_parameter.alb_arn[0].value
  alb_dns_name = local.props.alb.create ? module.alb[0].alb_dns_name : data.aws_ssm_parameter.alb_dns_name[0].value
  alb_sg_id = local.props.alb.create ? module.alb[0].security_group_id : data.aws_ssm_parameter.alb_sg_id[0].value
  alb_listener_arn = local.props.alb.create ? module.alb[0].https_listener_arn : data.aws_ssm_parameter.alb_listener_arn[0].value
}

# ECS Services - one module call per service
module "ecs" {
  for_each = local.props.ecs_services

  source = "./modules/ecs"

  region                        = var.region

  s3_bucket_name = module.s3[0].s3_bucket_name

  service_name = each.key
  service_config = merge(
    # Global defaults from ecs config (excluding environment - handled separately)
    {
      mount_gp3_volume         = local.props.ecs.mount_gp3_volume
      task_def                 = local.props.ecs.task_def
      autoscaling              = local.props.ecs.autoscaling
      max_autoscale_task_count = local.props.ecs.max_autoscale_task_count
      deploy_as_service        = local.props.ecs.deploy_as_service
      deploy_as_web_app        = local.props.ecs.deploy_as_web_app
      mount_efs                = local.props.ecs.mount_efs
      application_ports        = local.props.ecs.application_ports
      deployment               = local.props.ecs.deployment
    },
    # Service-specific overrides
    each.value,
    # Processed environment (global + service-specific, all values converted to strings)
    {
      environment = merge(
        lookup(local.props.ecs, "environment", {}),
        {
          for key, value in lookup(each.value, "environment", {}) :
          key => try(tostring(value), jsonencode(value))
          if key != "CONFIG"
        }
      )
    }
  )

  app_name    = local.app_name
  environment = var.environment
  vpc_id      = local.vpc_id
  vpc_cidr    = local.vpc_cidr
  subnet_ids  = data.aws_subnets.support_subnets.ids

  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.region

  ecs_cluster_name = module.ecs_cluster.cluster_name

  execution_role_arn             = module.ecs_cluster.execution_role_arn
  eventbridge_role_arn           = module.ecs_cluster.eventbridge_role_arn

  database_service_account_name = local.database_service_accounts[0].name
  domain_name                   = local.props.route53.domain_name
  route53_zone_id               = data.aws_route53_zone.cert_zone.zone_id
  alb_arn                       = local.alb_arn
  alb_dns_name                  = local.alb_dns_name
  alb_sg_id                     = local.alb_sg_id
  alb_listener_arn              = local.alb_listener_arn

  nats_url                       = module.nats.nats_url

  # Enable off-hours scaling for non-prod environments
  enable_off_hours_scaling = var.environment != "prod"

  depends_on = [module.ecs_cluster, module.database_service_accounts, module.nats, local.alb_listener_arn, local.alb_dns_name, local.alb_sg_id, local.alb_arn, local.vpc_id]
}

resource "aws_ssm_parameter" "openobserve_credentials" {
  name = "/${local.app_name}/fluentbit/credentials"
  type = "SecureString"
  value = jsonencode({
    http_User = "admin"
    http_Passwd = "placeholder"
  })
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "openobserve_otel_auth" {
  name = "/${local.app_name}/otel/auth"
  type = "SecureString"
  value = "placeholder"
  lifecycle {
    ignore_changes = [value]
  }
}