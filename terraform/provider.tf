variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = local.project_name
      Application     = local.app_name
      ManagedBy   = "terraform"
    }
  }
} 