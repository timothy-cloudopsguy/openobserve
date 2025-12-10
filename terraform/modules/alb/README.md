# ALB Module

This module creates a public Application Load Balancer (ALB) in AWS with the following components:

## Resources Created

- **Application Load Balancer**: Public ALB with cross-zone load balancing
- **Security Group**: Allows HTTP (80) and HTTPS (443) traffic from anywhere
- **HTTP Listener**: Redirects all HTTP traffic to HTTPS
- **HTTPS Listener**: Default action returns a simple "ALB is running" response
- **ACM Certificate**: SSL certificate for HTTPS (requires DNS validation)
- **SSM Parameter**: Stores the ALB ARN at `/${app_name}/alb/${env_name}/arn`

## Variables

| Variable | Description | Type | Required |
|----------|-------------|------|----------|
| app_name | Application name | string | Yes |
| env_name | Environment name | string | Yes |
| vpc_id | VPC ID where ALB will be created | string | Yes |
| public_subnet_ids | List of public subnet IDs for ALB | list(string) | Yes |
| region | AWS region | string | Yes |
| account_id | AWS account ID | string | Yes |
| route53_hosted_zones | Route53 hosted zones configuration for certificate validation | object | No |

## Outputs

| Output | Description |
|--------|-------------|
| alb_arn | ALB ARN |
| alb_dns_name | ALB DNS name |
| alb_zone_id | ALB zone ID for Route53 alias records |
| security_group_id | ALB security group ID |
| https_listener_arn | HTTPS listener ARN for adding rules |

## Usage

```hcl
module "alb" {
  source            = "./modules/alb"
  app_name          = "myapp"
  env_name          = "dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  region            = "us-east-1"
  account_id        = "123456789012"
}
```

## Notes

- The ALB is configured for public access with HTTP redirecting to HTTPS
- SSL certificates are created for each domain in `route53_hosted_zones.base_fqdns`
- Uses modern SSL policy `ELBSecurityPolicy-TLS13-1-2-2021-06` supporting TLS 1.3 and TLS 1.2
- DNS validation is performed using the hosted zones specified in `route53_hosted_zones.base_fqdns`
- Default HTTPS action returns a simple health check response
- ALB ARN is stored in SSM Parameter Store following the same pattern as VPC IDs
