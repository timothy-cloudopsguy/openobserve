# VPC Terraform Module

This module creates AWS VPC infrastructure based on the original CDK implementation. It supports:

## Features

- **VPC Flow Logs**: CloudWatch log group, IAM role, and service-linked role for VPC flow logging
- **Route53 Hosted Zones**: Optional creation of hosted zones with subdomains
- **Management VPC**: Optional management VPC with public and bastion subnets
- **Main VPCs**: Multiple VPCs with public, support, app, and persistence subnets
- **VPC Peering**: Automatic peering between management VPC and other VPCs
- **Security Groups**: CIS-compliant security groups for VPC peering
- **VPC Endpoints**: ECR Docker, S3, and DynamoDB endpoints for secure AWS service access
- **NAT Solutions**: Choose between AWS NAT Gateway or cost-effective EC2 NAT instances (fck_nat)
- **Dynamic CIDR**: Per-VPC automatic CIDR block generation using hash-based calculation

## Configuration

The module is configured via variables that map to the properties JSON file structure:

```hcl
module "vpc" {
  source = "./modules/vpc"

  app_name = "vpcs"
  env_name = "dev"
  props_file = "./properties.dev.json"

  create_mgmt_vpc = true

  mgmt_vpc = {
    CIDR = "10.254.0.0/16"
    subnet_cidr_mask = 20
    max_azs = 1
    ngw_count = 1
    peer_existing_vpcs = []
  }

  vpcs = [
    {
      name = "dev"
      create_vpc = true
      CIDR = ""
      subnet_cidr_mask = 20
      max_azs = 3
      ngw_count = 1
      fck_nat = true  # Use EC2 NAT instance instead of AWS NAT Gateway
      create_cidr_using_modulus = true  # Use hash-based CIDR calculation for this VPC
    }
  ]

  route53_hosted_zones = {
    create_zones = false
    domain_prefix = "develop"
    base_fqdns = ["example.com"]
    subdomain_names = []
  }

  region = "us-east-1"
  account_id = "123456789012"
}
```

## Properties File Structure

The module reads configuration from a JSON properties file:

```json
{
  "app_name": "vpcs",
  "create_mgmt_vpc": false,
  "route53_hosted_zones": {
    "create_zones": false,
    "domain_prefix": "develop",
    "base_fqdns": ["example.com"],
    "subdomain_names": []
  },
  "mgmt_vpc": {
    "CIDR": "10.254.0.0/16",
    "subnet_cidr_mask": 20,
    "max_azs": 1,
    "ngw_count": 1,
    "peer_existing_vpcs": []
  },
  "vpcs": [
    {
      "name": "dev",
      "create_vpc": true,
      "CIDR": "",
      "subnet_cidr_mask": 20,
      "max_azs": 3,
      "ngw_count": 1,
      "fck_nat": true,
      "create_cidr_using_modulus": true
    }
  ]
}
```

## FCK NAT Feature

When `fck_nat` is set to `true` in a VPC configuration, the module creates a cost-effective EC2 NAT instance instead of using AWS NAT Gateway:

- **Cost Savings**: t4g.nano instance (~$3/month) vs NAT Gateway (~$30-40/month)
- **Automatic Setup**: EC2 instance with:
  - FCK NAT public AMI (`fck-nat-al2023-hvm*`) - dynamically looked up by wildcard pattern for latest version in multi-region support
  - t4g.nano instance type
  - EIP attached for outbound internet access
  - Source/destination checks disabled
  - iptables configured for NAT functionality
  - User data script for automatic NAT configuration

The NAT instance is placed in the public subnet and private subnets route outbound traffic through it instead of the NAT Gateway.

**Note**: EC2 NAT instances have lower throughput limits compared to NAT Gateway. For high-traffic workloads, consider using NAT Gateway instead.

## Outputs

The module provides the following outputs:

- `vpc_log_group_name`: CloudWatch log group name for VPC flow logs
- `properties_file`: Properties file path
- `mgmt_vpc_id`: Management VPC ID (if created)
- `mgmt_vpc_cidr`: Management VPC CIDR (if created)
- `main_vpc_ids`: Map of VPC names to VPC IDs
- `main_vpc_cidrs`: Map of VPC names to VPC CIDRs
- `vpc_peering_connections`: Map of peering connection names to IDs
- `vpc_peering_security_groups`: Map of security group names to IDs
- `route53_hosted_zones`: Map of hosted zone names to IDs
- `s3_vpc_endpoints`: Map of VPC names to S3 VPC endpoint IDs
- `dynamodb_vpc_endpoints`: Map of VPC names to DynamoDB VPC endpoint IDs
