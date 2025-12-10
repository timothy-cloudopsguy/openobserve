# VPC Flow Logs Infrastructure
resource "aws_cloudwatch_log_group" "vpc_log_group" {
  name              = "/aws/vpc/flowlogs"
  retention_in_days = 30
}

resource "aws_iam_role" "vpc_log_group_role" {
  name = "${var.app_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

# SSM Default Host Management Configuration - Enables Systems Manager console experience
# This replicates what the "Enable Systems Manager" button does in the console
resource "aws_ssm_service_setting" "default_host_management" {
  setting_id    = "/ssm/managed-instance/default-ec2-instance-management-role"
  setting_value = "AmazonSSMManagedInstanceCore"
}

# Note: AmazonSSMManagedInstanceCore is an AWS-managed role created automatically
# when you enable Systems Manager. It cannot be created manually as it starts with "Amazon".
# We just reference it in the service setting below.

# Note: AWSServiceRoleForAmazonSSM is a service-linked role that AWS creates automatically
# when you first use Systems Manager features. It already exists in your account, so we don't
# need to create it here. If it didn't exist, AWS would create it when you enable SSM features.

# Alternative: CloudFormation-based Quick Setup (closer to what the console button does)
# Uncomment this section if you prefer the CloudFormation approach
/*
resource "aws_cloudformation_stack" "ssm_quick_setup" {
  name = "AWS-QuickSetup-SSM"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "AWS Systems Manager Quick Setup Host Management"

    Resources = {
      # Note: Both AWSServiceRoleForAmazonSSM and AmazonSSMManagedInstanceCore
      # are AWS-managed roles created automatically when SSM is enabled

      DefaultHostManagementSetting = {
        Type = "AWS::SSM::ServiceSetting"
        Properties = {
          SettingId = "/ssm/managed-instance/default-ec2-instance-management-role"
          SettingValue = "AmazonSSMManagedInstanceCore"
        }
      }
    }
  })
}
*/

resource "aws_ssm_parameter" "vpc_log_group_ssm" {
  name  = "/${var.app_name}/vpc/${var.vpc.name}/log_group_name"
  type  = "String"
  value = aws_cloudwatch_log_group.vpc_log_group.name
} 

# resource "aws_route53_zone" "subdomain_hosted_zones" {
#   for_each = var.route53_hosted_zones.create_zones ? {
#     for pair in flatten([
#       for base_fqdn in var.route53_hosted_zones.base_fqdns : [
#         for subdomain in var.route53_hosted_zones.subdomain_names : {
#           key = "${subdomain}.${var.route53_hosted_zones.domain_prefix != null ? var.route53_hosted_zones.domain_prefix : ""}.${base_fqdn}"
#           value = {
#             subdomain = subdomain
#             base_fqdn = base_fqdn
#           }
#         }
#       ]
#     ]) : pair.key => pair.value
#   } : {}

#   name = each.key

#   comment = "Created by ${var.app_name}"
# }


# Calculate CIDR blocks using modulus if needed (per VPC configuration)
locals {
  cidr_block = var.vpc.create_cidr_using_modulus ? format("10.%d.0.0/16", parseint(substr(md5("${var.vpc.name}-${var.region}"), 0, 8), 16) % 252) : var.vpc.CIDR
}

# Main VPCs
resource "aws_vpc" "main_vpcs" {
  cidr_block = local.cidr_block

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.vpc.name
  }
}

resource "aws_ssm_parameter" "vpc_ids" {
  name  = "/${var.app_name}/vpc/${var.vpc.name}/id"
  type  = "String"
  value = aws_vpc.main_vpcs.id

  tags = {
    Name = "${var.vpc.name}-vpc-id"
  }
}

resource "aws_ssm_parameter" "cidr_blocks" {
  name  = "/${var.app_name}/vpc/${var.vpc.name}/cidr"
  type  = "String"
  value = aws_vpc.main_vpcs.cidr_block

  tags = {
    Name = "${var.vpc.name}-vpc-cidr"
  }
}


# Public subnets for main VPCs (one per AZ up to max_azs)
resource "aws_subnet" "main_public_subnets" {
  for_each = {
    for az_index in range(0, var.vpc.max_azs) : "${var.vpc.name}-pub-${az_index}" => {
      az_index   = az_index
      cidr_index = az_index * 4 # 0, 4, 8, 12... for public subnets
    }
  }
  vpc_id                  = aws_vpc.main_vpcs.id
  cidr_block              = cidrsubnet(aws_vpc.main_vpcs.cidr_block, var.vpc.subnet_cidr_mask - 16, each.value.cidr_index)
  availability_zone       = data.aws_availability_zones.available.names[each.value.az_index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc.name}-pub-${each.value.az_index + 1}"
    Type = "public"
  }
}

# Support subnets for main VPCs (one per AZ up to max_azs)
resource "aws_subnet" "main_support_subnets" {
  for_each = {
    for az_index in range(0, var.vpc.max_azs) : "${var.vpc.name}-support-${az_index}" => {
      az_index   = az_index
      cidr_index = az_index * 4 + 1 # 1, 5, 9, 13... for support subnets
    }
  }

  vpc_id            = aws_vpc.main_vpcs.id
  cidr_block        = cidrsubnet(aws_vpc.main_vpcs.cidr_block, var.vpc.subnet_cidr_mask - 16, each.value.cidr_index)
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = {
    Name = "${var.vpc.name}-support-${each.value.az_index + 1}"
    Type = "support"
  }
}

# App subnets for main VPCs (one per AZ up to max_azs)
resource "aws_subnet" "main_app_subnets" {
  for_each = {
    for az_index in range(0, var.vpc.max_azs) : "${var.vpc.name}-app-${az_index}" => {
      az_index   = az_index
      cidr_index = az_index * 4 + 2 # 2, 6, 10, 14... for app subnets
    }
  }

  vpc_id            = aws_vpc.main_vpcs.id
  cidr_block        = cidrsubnet(aws_vpc.main_vpcs.cidr_block, var.vpc.subnet_cidr_mask - 16, each.value.cidr_index)
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = {
    Name = "${var.vpc.name}-app-${each.value.az_index + 1}"
    Type = "app"
  }
}

# Persistence subnets for main VPCs (one per AZ up to max_azs)
resource "aws_subnet" "main_persistence_subnets" {
  for_each = {
    for az_index in range(0, var.vpc.max_azs) : "${var.vpc.name}-persistence-${az_index}" => {
      az_index   = az_index
      cidr_index = az_index * 4 + 3 # 3, 7, 11, 15... for persistence subnets
    }
  }

  vpc_id            = aws_vpc.main_vpcs.id
  cidr_block        = cidrsubnet(aws_vpc.main_vpcs.cidr_block, var.vpc.subnet_cidr_mask - 16, each.value.cidr_index)
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = {
    Name = "${var.vpc.name}-persistence-${each.value.az_index + 1}"
    Type = "persistence"
  }
}

# Internet Gateway for main VPCs
resource "aws_internet_gateway" "main_igws" {
  vpc_id = aws_vpc.main_vpcs.id

  tags = {
    Name = "${var.vpc.name}-igw"
  }
}

# NAT Gateway for main VPCs (only when fck_nat is false)
resource "aws_eip" "main_nat_eips" {
  for_each = var.vpc.create && !var.vpc.fck_nat ? {
    "${var.vpc.name}" = var.vpc
  } : {}

  domain = "vpc"

  tags = {
    Name = "${var.vpc.name}-nat"
  }
}

resource "aws_nat_gateway" "main_nat_gateways" {
  for_each = var.vpc.create && !var.vpc.fck_nat ? {
    "${var.vpc.name}" = var.vpc
  } : {}

  allocation_id = aws_eip.main_nat_eips[var.vpc.name].id
  subnet_id     = aws_subnet.main_public_subnets["${var.vpc.name}-pub-0"].id

  tags = {
    Name = "${var.vpc.name}-nat"
  }
}

# FCK-NAT module integration (only when fck_nat is true)
module "fck_nat" {
  count = var.vpc.create && var.vpc.fck_nat ? 1 : 0

  source = "git::https://github.com/RaJiska/terraform-aws-fck-nat.git"

  name                = "${var.vpc.name}-fck-nat"
  vpc_id              = aws_vpc.main_vpcs.id
  subnet_id           = aws_subnet.main_public_subnets["${var.vpc.name}-pub-0"].id
  update_route_tables = true
  route_tables_ids    = {
    "private" = aws_route_table.main_private_rts[0].id
  } 

  # Optional configurations:
  # ha_mode              = true                 # Enables high-availability mode
  # eip_allocation_ids   = ["eipalloc-abc1234"] # Allocation ID of an existing EIP
  # use_cloudwatch_agent = true                 # Enables Cloudwatch agent and have metrics reported
}

# Route tables for main VPCs
resource "aws_route_table" "main_public_rts" {
  count = var.vpc.create ? 1 : 0

  vpc_id = aws_vpc.main_vpcs.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igws.id
  }

  tags = {
    Name = "${var.vpc.name}-public-rt"
  }
}

resource "aws_route_table" "main_private_rts" {
  count = var.vpc.create ? 1 : 0

  vpc_id = aws_vpc.main_vpcs.id

  # Route for NAT Gateway (when fck_nat is false)
  # Note: When fck_nat is true, the fck-nat module automatically manages routes
  dynamic "route" {
    for_each = var.vpc.fck_nat ? [] : [1]
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main_nat_gateways.id
    }
  }

  tags = {
    Name = "${var.vpc.name}-private-rt"
  }
}

# Route table associations for main VPCs (one per subnet per VPC)
resource "aws_route_table_association" "main_public_rta" {
  for_each = var.vpc.create ? aws_subnet.main_public_subnets : {}
  subnet_id      = aws_subnet.main_public_subnets[each.key].id
  route_table_id = aws_route_table.main_public_rts[0].id
}

resource "aws_route_table_association" "main_support_rta" {
  for_each = var.vpc.create ? aws_subnet.main_support_subnets : {}

  subnet_id      = aws_subnet.main_support_subnets[each.key].id
  route_table_id = aws_route_table.main_private_rts[0].id
}

resource "aws_route_table_association" "main_app_rta" {
  for_each = var.vpc.create ? aws_subnet.main_app_subnets : {}

  subnet_id      = aws_subnet.main_app_subnets[each.key].id
  route_table_id = aws_route_table.main_private_rts[0].id
}

resource "aws_route_table_association" "main_persistence_rta" {
  for_each = var.vpc.create ? aws_subnet.main_persistence_subnets : {}

  subnet_id      = aws_subnet.main_persistence_subnets[each.key].id
  route_table_id = aws_route_table.main_private_rts[0].id
}

# VPC Endpoint Route Table Associations for Gateway Endpoints
resource "aws_vpc_endpoint_route_table_association" "s3_private_rta" {
  count = var.vpc.create ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = aws_route_table.main_private_rts[0].id
}

resource "aws_vpc_endpoint_route_table_association" "dynamodb_private_rta" {
  count = var.vpc.create ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb[0].id
  route_table_id  = aws_route_table.main_private_rts[0].id
}

# VPC Flow Logs for main VPCs
resource "aws_flow_log" "main_vpc_flow_logs" {
  count = var.vpc.create ? 1 : 0

  vpc_id               = aws_vpc.main_vpcs.id
  traffic_type         = "REJECT"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_log_group.arn
  iam_role_arn         = aws_iam_role.vpc_log_group_role.arn
}

# ECR Docker Interface VPC Endpoint ($8/month)
# resource "aws_vpc_endpoint" "ecr_docker" {
#   for_each = {
#     for vpc in var.vpcs : vpc.name => vpc if vpc.create
#   }

#   vpc_id              = aws_vpc.main_vpcs[each.key].id
#   service_name        = "com.amazonaws.${var.region}.ecr.dkr"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = [aws_subnet.main_support_subnets[each.key].id]
#   security_group_ids  = [aws_security_group.vpc_endpoint_sg[each.key].id]
#   private_dns_enabled = true

#   tags = {
#     Name = "${each.key}-ecr-docker-endpoint"
#   }
# }

# S3 Gateway VPC Endpoint (FREE)
resource "aws_vpc_endpoint" "s3" {
  count = var.vpc.create ? 1 : 0

  vpc_id            = aws_vpc.main_vpcs.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.vpc.name}-s3-endpoint"
  }
}

# DynamoDB Gateway VPC Endpoint (FREE)
resource "aws_vpc_endpoint" "dynamodb" {
  count = var.vpc.create ? 1 : 0

  vpc_id            = aws_vpc.main_vpcs.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.vpc.name}-dynamodb-endpoint"
  }
}

resource "aws_security_group" "vpc_endpoint_sg" {
  count = var.vpc.create ? 1 : 0

  name        = "${var.vpc.name}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main_vpcs.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpcs.cidr_block]
  }

  tags = {
    Name = "${var.vpc.name}-vpc-endpoint-sg"
  }
}

# Note: Security groups for fck-nat instances are managed by the fck-nat module


# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Note: FCK NAT AMI lookup is handled by the fck-nat module


# Default Security Group Restrictions (CIS Compliance)
resource "aws_default_security_group" "default_sg_restrictions" {

  count = var.vpc.create ? 1 : 0

  vpc_id = aws_vpc.main_vpcs.id

  # Remove all default ingress rules
  # Note: Terraform doesn't have direct support for restricting default SGs like CDK custom resources
  # This is a placeholder - actual implementation would require custom resources or manual intervention
}
