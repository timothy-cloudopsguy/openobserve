variable "app_name" {
  description = "Application name"
  type        = string
}

variable "env_name" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "route53_hosted_zones" {
  description = "Route53 hosted zones configuration"
  type = object({
    create_zones    = optional(bool, false)
    domain_prefix   = optional(string, "")
    base_fqdns      = optional(list(string), [])
    subdomain_names = optional(list(string), [])
  })
  default = {
    create_zones    = false
    domain_prefix   = ""
    base_fqdns      = []
    subdomain_names = []
  }
}
