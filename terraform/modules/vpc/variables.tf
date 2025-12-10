variable "app_name" {
  description = "Application name"
  type        = string
}

variable "env_name" {
  description = "Environment name"
  type        = string
}

variable "props_file" {
  description = "Properties file name"
  type        = string
}

variable "vpc" {
  description = "VPC to create"
  type = object({
    name                      = string
    create                = bool
    CIDR                      = string
    subnet_cidr_mask          = number
    max_azs                   = number
    ngw_count                 = number
    fck_nat                   = optional(bool, false)
    create_cidr_using_modulus = optional(bool, false)
  })
  default = {
    name = "main"
    create = true
    CIDR = "10.0.0.0/16"
    subnet_cidr_mask = 20
    max_azs = 3
    ngw_count = 1
    fck_nat = false
  }
}

# variable "route53_hosted_zones" {
#   description = "Route53 hosted zones configuration"
#   type = object({
#     create_zones    = bool
#     domain_prefix   = optional(string)
#     base_fqdns      = list(string)
#     subdomain_names = list(string)
#   })
#   default = {
#     create_zones    = false
#     domain_prefix   = null
#     base_fqdns      = []
#     subdomain_names = []
#   }
# }

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}
