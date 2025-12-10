variable "app_name" { type = string }
variable "env_name" { type = string }
variable "props_file" { type = string }
variable "organization_id" { type = string }
variable "aws_org_ids" { type = list(string) }
variable "region" { type = string }

locals {
  bucket_name = "${var.organization_id}-openobserve-data"
}

resource "aws_s3_bucket" "build_artifacts" {
  bucket = local.bucket_name

  tags = {
    Environment = var.env_name
    Application = var.app_name
    Purpose     = "openObserve data"
  }
}

resource "aws_s3_bucket_versioning" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "build_artifacts_policy" {
  statement {
    sid    = "OrgReadAccess"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketVersions"
    ]
    resources = [
      aws_s3_bucket.build_artifacts.arn,
      "${aws_s3_bucket.build_artifacts.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = var.aws_org_ids
    }
  }

  statement {
    sid    = "CICDWriteAccess"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketVersions"
    ]
    resources = [
      aws_s3_bucket.build_artifacts.arn,
      "${aws_s3_bucket.build_artifacts.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = var.aws_org_ids
    }
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/cicdMgmt"]
    }
  }
}

resource "aws_s3_bucket_policy" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id
  policy = data.aws_iam_policy_document.build_artifacts_policy.json
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for build artifacts"
  value       = aws_s3_bucket.build_artifacts.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for build artifacts"
  value       = aws_s3_bucket.build_artifacts.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.build_artifacts.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.build_artifacts.bucket_regional_domain_name
}

output "env_name" {
  value = var.env_name
}

output "props_file" {
  value = var.props_file
}
