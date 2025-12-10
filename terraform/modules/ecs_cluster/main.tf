
locals {
  suffix = lower(random_id.suffix.hex)
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 2
}

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "${var.app_name}-cluster-${local.suffix}"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = {
    Name        = "${var.app_name}-cluster-${local.suffix}"
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "ecs_cluster_arn" {
  name  = "/${var.app_name}/ecs/cluster/arn"
  type  = "String"
  value = aws_ecs_cluster.this.arn
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}


# IAM Role for ECS task execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-ecs-execution-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-ecs-execution-role-${local.suffix}"
  }
}

# # Check if ECS service-linked role already exists
# data "aws_iam_roles" "existing_roles" {
#   name_regex = "^AWSServiceRoleForECS$"
# }

# # Create ECS service-linked role only if it doesn't exist
# resource "aws_iam_service_linked_role" "ecs" {
#   count = length(data.aws_iam_roles.existing_roles.names) == 0 ? 1 : 0

#   aws_service_name = "ecs.amazonaws.com"
#   description      = "Service-linked role for Amazon ECS"
# }

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  # depends_on = [aws_iam_service_linked_role.ecs]
}

resource "aws_iam_policy" "ssm_parameters_read_policy" {
  name = "${var.app_name}-ssm-parameters-read-policy-${local.suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:Get*"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/${var.app_name}/ecs/*",
          "arn:aws:ssm:*:*:parameter/${var.app_name}/db-service-accounts/*",
          "arn:aws:ssm:*:*:parameter/${var.app_name}/valkey-service-account/users/*"
        ]
      } 
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_parameters_read_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ssm_parameters_read_policy.arn
}

# SSM messaging policy for ECS execute command
resource "aws_iam_policy" "ecs_execute_command_policy" {
  name = "${var.app_name}-ecs-execute-command-policy-${local.suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = [
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_ecs_cluster.this.name}",
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_ecs_cluster.this.name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetConnectionStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execute_command_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_execute_command_policy.arn
}

# IAM Role for EventBridge to run ECS tasks
resource "aws_iam_role" "eventbridge_ecs_role" {
  name = "${var.app_name}-eventbridge-ecs-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-eventbridge-ecs-role-${local.suffix}"
  }
}

resource "aws_iam_role_policy_attachment" "eventbridge_ecs_policy" {
  role       = aws_iam_role.eventbridge_ecs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Off-hours scaling infrastructure (only for non-prod environments)
locals {
  enable_off_hours_scaling = var.environment != "prod" && try(var.off_hours_scaling.enabled, false)
}

# IAM Role for Lambda scaling function
resource "aws_iam_role" "scaling_lambda_role" {
  count = local.enable_off_hours_scaling ? 1 : 0

  name = "${var.app_name}-scaling-lambda-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-scaling-lambda-role-${local.suffix}"
  }
}

# IAM policy for Lambda to scale ECS services and access SSM
resource "aws_iam_policy" "scaling_lambda_policy" {
  count = local.enable_off_hours_scaling ? 1 : 0

  name = "${var.app_name}-scaling-lambda-policy-${local.suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:ListServices",
          "ecs:UpdateService"
        ]
        Resource = [
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_ecs_cluster.this.name}",
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_ecs_cluster.this.name}/*",
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.app_name}/ecs/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app_name}-scaling-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "scaling_lambda_policy" {
  count = local.enable_off_hours_scaling ? 1 : 0

  role       = aws_iam_role.scaling_lambda_role[0].name
  policy_arn = aws_iam_policy.scaling_lambda_policy[0].arn
}


# Lambda function for scaling
data "archive_file" "scaling_lambda_package" {
  count = local.enable_off_hours_scaling ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/scaling_lambda.zip"
}

resource "aws_lambda_function" "scaling_function" {
  count = local.enable_off_hours_scaling ? 1 : 0

  filename         = data.archive_file.scaling_lambda_package[0].output_path
  function_name    = "${var.app_name}-scaling-${local.suffix}"
  role            = aws_iam_role.scaling_lambda_role[0].arn
  handler         = "scaling_function.lambda_handler"
  runtime         = "python3.13"
  timeout         = 300
  source_code_hash = data.archive_file.scaling_lambda_package[0].output_sha256

  environment {
    variables = {
      ECS_CLUSTER_NAME = aws_ecs_cluster.this.name
      APP_NAME         = var.app_name
      ENVIRONMENT      = var.environment
    }
  }

  tags = {
    Name        = "${var.app_name}-scaling-${local.suffix}"
    Environment = var.environment
  }
}

# EventBridge rules for scaling schedule
resource "aws_cloudwatch_event_rule" "scale_down" {
  count = local.enable_off_hours_scaling ? 1 : 0

  name                = "${var.app_name}-scale-down-${local.suffix}"
  description         = "Scale down ECS services at night (weekdays only)"
  schedule_expression = var.off_hours_scaling.scale_down_cron

  tags = {
    Name        = "${var.app_name}-scale-down-${local.suffix}"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_rule" "scale_up" {
  count = local.enable_off_hours_scaling ? 1 : 0

  name                = "${var.app_name}-scale-up-${local.suffix}"
  description         = "Scale up ECS services in the morning (weekdays only)"
  schedule_expression = var.off_hours_scaling.scale_up_cron

  tags = {
    Name        = "${var.app_name}-scale-up-${local.suffix}"
    Environment = var.environment
  }
}

# EventBridge targets for scaling
resource "aws_cloudwatch_event_target" "scale_down" {
  count = local.enable_off_hours_scaling ? 1 : 0

  rule      = aws_cloudwatch_event_rule.scale_down[0].name
  target_id = "ScaleDownTarget"
  arn       = aws_lambda_function.scaling_function[0].arn

  input = jsonencode({
    action = "scale_down"
  })
}

resource "aws_cloudwatch_event_target" "scale_up" {
  count = local.enable_off_hours_scaling ? 1 : 0

  rule      = aws_cloudwatch_event_rule.scale_up[0].name
  target_id = "ScaleUpTarget"
  arn       = aws_lambda_function.scaling_function[0].arn

  input = jsonencode({
    action = "scale_up"
  })
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "scale_down" {
  count = local.enable_off_hours_scaling ? 1 : 0

  statement_id  = "AllowEventBridgeScaleDown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaling_function[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_down[0].arn
}

resource "aws_lambda_permission" "scale_up" {
  count = local.enable_off_hours_scaling ? 1 : 0

  statement_id  = "AllowEventBridgeScaleUp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaling_function[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_up[0].arn
}


resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "${var.app_name}.local"
  vpc         = var.vpc_id
  description = "Internal service discovery for ${var.app_name}"
  tags = {
    Name        = "${var.app_name}-service-discovery"
    Environment = var.environment
  }
}