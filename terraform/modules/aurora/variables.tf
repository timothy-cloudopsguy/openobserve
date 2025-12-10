variable "app_name" {
  description = "Application name"
  type        = string
}

variable "env_name" {
  description = "Environment name"
  type        = string
}

variable "iac_core_stack_name" {
  description = "Resolved iac-core stack name (e.g., iacCoreDev)"
  type        = string
}

variable "aurora_config" {
  description = "Aurora configuration"
  type        = map(any)
}

variable "route53_domain_name" {
  description = "Route53 domain name for DNS entries"
  type        = string
}

variable "route53_ttl" {
  description = "TTL for Route53 DNS records"
  type        = number
  default     = 60
}
