locals {
  # Load the existing properties files from the cdk directory (properties.dev.json / properties.prod.json)
  props_file = "${path.module}/properties.${var.environment}.json"
  props_raw  = file(local.props_file)

  # First pass: decode JSON to extract app_name and domain_name for replacement
  props_temp = jsondecode(local.props_raw)

  # Expose useful values
  env_name    = var.environment
  app_name    = length(trimspace(var.app_name)) > 0 ? var.app_name : "${local.props_temp.app_name}${title(var.environment)}"
  project_name = local.props.project_name
  domain_name = local.props_temp.route53.domain_name
  ecr_repo = "${local.props_temp.ecr.repository_account}.dkr.ecr.${local.props_temp.ecr.repository_region}.amazonaws.com"

  # Second pass: replace placeholders in the raw JSON string
  props_replaced = replace(replace(replace(replace(local.props_raw, "__APP_NAME__", local.app_name), "__ENVIRONMENT__", local.env_name), "__DOMAIN_NAME__", local.domain_name), "__ECR_REPO__", local.ecr_repo)

  # Final props with placeholders resolved
  props = jsondecode(local.props_replaced)

  # Resolve iac-core stack name: iac_core_name + capitalized environment
  iac_core_stack_name = "${local.props.iac_core_name}${title(var.environment)}"

  # Aurora configuration
  aurora_config                       = lookup(local.props, "aurora", {})

  # Route53 configuration
  route53_config      = lookup(local.props, "route53", {})
  route53_domain_name = lookup(local.route53_config, "domain_name", "")
  route53_ttl         = lookup(local.route53_config, "ttl", 60)

  # Database service accounts configuration
  database_service_accounts = lookup(local.props, "database_service_accounts", [])
} 