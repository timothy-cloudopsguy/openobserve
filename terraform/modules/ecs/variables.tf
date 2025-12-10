variable "region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "service_config" {
  description = "Configuration for this specific service (merged with defaults)"
  type = object({
    mount_gp3_volume   = optional(bool, false)
    repository_name    = string
    image_tag          = string
    command            = any
    working_dir        = string
    schedule           = optional(string)
    deploy_as_service  = optional(bool, true)
    deploy_as_web_app  = optional(bool, false)
    alb_priority       = optional(number, 100)
    mount_efs          = optional(bool, false)
    application_ports  = optional(object({
      ingress_internal = optional(object({
        tcp = optional(list(number), [80])
      }), {})
    }), {})
    environment        = optional(map(any), {})
    autoscaling        = optional(any, {})
    deployment         = optional(any, {})
    task_def = optional(object({
      desired_count    = optional(number, 1)
      vCPU             = optional(number, 512)
      vRAM             = optional(number, 1024)
      cpu_architecture = optional(string, "arm64")
      spot             = optional(bool, true)
    }), {})
    max_autoscale_task_count = optional(number, 1)
  })
}

variable "app_name" {
  description = "Application name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS resources will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS services"
  type        = list(string)
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}


variable "execution_role_arn" {
  description = "IAM role ARN for ECS task execution"
  type        = string
}


variable "eventbridge_role_arn" {
  description = "IAM role ARN for EventBridge to run ECS tasks"
  type        = string
}

variable "database_service_account_name" {
  description = "Name of the database service account"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "enable_off_hours_scaling" {
  description = "Whether to enable off-hours scaling for this service"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for SSL certificate creation"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for certificate validation records"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN for ECS services"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name for CNAME records"
  type        = string
}

variable "alb_sg_id" {
  description = "ALB security group ID for ECS security groups"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB listener ARN for SSL certificate attachment"
  type        = string
}

variable "nats_url" {
  description = "NATS URL for ECS services"
  type        = string
}