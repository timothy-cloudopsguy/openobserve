variable "app_name" {
  description = "Application name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "enable_container_insights" {
  description = "Whether to enable container insights for the ECS cluster"
  type        = bool
  default     = false
}

variable "region" {
  description = "Region"
  type        = string
}

variable "off_hours_scaling" {
  description = "Configuration for off-hours scaling"
  type = object({
    enabled         = bool
    scale_down_cron = string
    scale_up_cron   = string
    scale_to_zero   = bool
  })
  default = {
    enabled         = false
    scale_down_cron = "cron(0 22 ? * MON-FRI *)"
    scale_up_cron   = "cron(0 8 ? * MON-FRI *)"
    scale_to_zero   = true
  }
}