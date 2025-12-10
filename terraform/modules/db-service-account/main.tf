# Data sources to pull VPC and subnet information from iac-core stack
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.iac_core_stack_name}/vpc/${lower(var.env_name)}/id"
}

data "aws_ssm_parameter" "vpc_cidr" {
  name = "/${var.iac_core_stack_name}/vpc/${lower(var.env_name)}/cidr"
}

data "aws_subnets" "support_subnets" {
  filter {
    name   = "tag:Type"
    values = ["support"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_ssm_parameter.vpc_id.value]
  }
}


locals {
  suffix = lower(random_id.suffix.hex)
}

resource "random_id" "suffix" {
  byte_length = 2
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-db-service-account-lambda-${var.env_name}-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-db-service-account-lambda-${var.env_name}-${local.suffix}"
    Environment = var.env_name
    ManagedBy   = "terraform"
  }
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.app_name}-db-service-account-lambda-${var.env_name}-${local.suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.aurora_master_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter${var.ssm_parameter_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:AddTagsToResource"
        ]
        Resource = "arn:aws:ssm:*:*:parameter*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Package Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/lambda.zip"
}

# # Trigger for detecting layer file changes
# resource "null_resource" "lambda_layer_trigger" {
#   triggers = {
#     # Hash all files in the layer-content directory to detect changes
#     layer_dir_hash = sha256(join("", [
#       for f in fileset("${path.module}/layer-content", "**/*") :
#       filesha256("${path.module}/layer-content/${f}")
#     ]))
#   }
# }

# Archive the Lambda layer
data "archive_file" "lambda_layer_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-layer.zip"
  source_dir  = "${path.module}/layer-content"

  # Depend on the trigger to force recreation when layer files change
  # depends_on = [null_resource.lambda_layer_trigger]
}

# Create the Lambda layer
resource "aws_lambda_layer_version" "db_service_account_dependencies" {
  layer_name          = "${var.app_name}-dependencies-${local.suffix}"
  compatible_runtimes = ["python3.13"]
  filename            = data.archive_file.lambda_layer_zip.output_path
  source_code_hash    = data.archive_file.lambda_layer_zip.output_sha256
}

# Security group for Lambda function
resource "aws_security_group" "lambda_security_group" {
  name        = "${var.app_name}-lambda-security-group-${var.env_name}-${local.suffix}"
  description = "Security group for Lambda function"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value
}

# Allow Lambda function to access the Aurora cluster
resource "aws_security_group_rule" "lambda_access_internet" {
  security_group_id = aws_security_group.lambda_security_group.id
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# Lambda function
resource "aws_lambda_function" "db_service_account" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.app_name}-db-service-account-${var.service_account_name}-${var.env_name}-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda.lambda_handler"
  runtime         = "python3.13"
  source_code_hash    = data.archive_file.lambda_zip.output_sha256
  timeout         = 300
  memory_size     = 256
  layers          = [aws_lambda_layer_version.db_service_account_dependencies.arn]

  vpc_config {
    subnet_ids = data.aws_subnets.support_subnets.ids
    security_group_ids = [aws_security_group.lambda_security_group.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.env_name
    }
  }

  tags = {
    Name             = "${var.app_name}-db-service-account-${var.service_account_name}-${var.env_name}-${local.suffix}"
    Environment      = var.env_name
    ServiceAccount   = var.service_account_name
    ManagedBy        = "terraform"
  }
}

# Invoke Lambda function to create service account
resource "aws_lambda_invocation" "create_service_account" {
  function_name = aws_lambda_function.db_service_account.function_name

  input = jsonencode({
    service_account_name = var.service_account_name
    database_name        = var.database_name
    permissions          = var.permissions
    tables               = var.tables
    schema_permissions   = var.schema_permissions
    database_privileges  = var.database_privileges
    aurora_endpoint      = var.aurora_endpoint
    aurora_port          = var.aurora_port
    master_secret_arn    = var.aurora_master_secret_arn
    ssm_parameter_name   = var.ssm_parameter_name
    update_permissions   = var.update_permissions
  })

  depends_on = [aws_iam_role_policy.lambda_policy]

  # Add a small delay to allow IAM policy propagation
  # IAM changes can take up to a few minutes to propagate across AWS

  # This ensures the Lambda is only invoked when the configuration changes
  triggers = {
    service_account_name  = var.service_account_name
    database_name         = var.database_name
    permissions           = join(",", sort(var.permissions))
    tables                = join(",", sort(var.tables))
    schema_permissions    = join(",", sort(var.schema_permissions))
    database_privileges   = join(",", sort(var.database_privileges))
    aurora_endpoint       = var.aurora_endpoint
    aurora_port           = var.aurora_port
    master_secret_arn     = var.aurora_master_secret_arn
    update_permissions    = var.update_permissions
    lambda_code_hash      = aws_lambda_function.db_service_account.source_code_hash
  }
}
