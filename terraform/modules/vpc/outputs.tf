output "vpc_log_group_name" {
  description = "VPC flow logs CloudWatch log group name"
  value       = aws_cloudwatch_log_group.vpc_log_group.name
}

output "properties_file" {
  description = "Properties file name"
  value       = var.props_file
}

# output "route53_hosted_zones" {
#   description = "Route53 hosted zone IDs"
#   value = merge(
#     {
#       for zone in aws_route53_zone.hosted_zones : zone.name => zone.id
#     },
#     {
#       for zone in aws_route53_zone.subdomain_hosted_zones : zone.name => zone.id
#     }
#   )
# }

output "s3_vpc_endpoints" {
  description = "S3 VPC endpoint IDs"
  value = {
    "${var.vpc.name}" = aws_vpc_endpoint.s3[0].id
  }
}

output "dynamodb_vpc_endpoints" {
  description = "DynamoDB VPC endpoint IDs"
  value = {
    "${var.vpc.name}" = aws_vpc_endpoint.dynamodb[0].id
  }
}

output "public_subnet_ids" {
  description = "Public subnet IDs by VPC name"
  value = {
    "${var.vpc.name}" = [
      for subnet_key, subnet in aws_subnet.main_public_subnets :
      subnet.id if split("-", subnet_key)[0] == var.vpc.name
    ]
  }
}

output "vpc_ids" {
  description = "VPC IDs by VPC name"
  value = {
    "${var.vpc.name}" = aws_vpc.main_vpcs.id
  }
}

output "cidr_blocks" {
  description = "VPC CIDR blocks by VPC name"
  value = {
    "${var.vpc.name}" = aws_vpc.main_vpcs.cidr_block
  }
}
