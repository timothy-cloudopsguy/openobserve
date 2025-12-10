variable "aws_region" {
    type = string
}

variable "app_name" {
    type = string
}

variable "env" {
    type = string
}

variable "vpc_id" {
    type = string
}

variable "cluster_arn" {
    type = string
}

variable "subnet_ids" {
    type = list(string)
}

variable "image" {
    type = string
}

variable "service_discovery_namespace_id" {
  description = "Service Discovery Namespace ID"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for ECS task execution"
  type        = string
}

variable "desired_count" {
  description = "Number of NATS server instances to run (should be 3+ for clustering)"
  type        = number
  default     = 3
}