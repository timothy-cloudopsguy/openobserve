
locals {
  # Extract application port from application_ports configuration
  application_port = try(var.service_config.application_ports.ingress_internal.tcp[0], 80)

  # Process environment variables - separate regular env vars from secrets
  # CONFIG is handled as a secret, so exclude it from environment variables
  environment = {
    for key, value in var.service_config.environment :
    key => value
    if value != "SSM" && value != "SECRET" && key != "CONFIG"
  }

  # Service-specific secrets (SSM/SECRET marked variables + CONFIG)
  service_secrets = merge(
    # Variables explicitly marked as SSM or SECRET
    { for key, value in var.service_config.environment :
      key => {
        type = value
        name = "/${var.app_name}/ecs/${var.service_name}/${key}"
      } if value == "SSM" || value == "SECRET"
    }
  )

  # All secrets (service-specific overrides)
  all_secrets = local.service_secrets

  # Deployment configuration with defaults
  deployment = {
    minimum_healthy_percent = var.service_config.deployment.minimum_healthy_percent
    maximum_percent = var.service_config.deployment.maximum_percent,
    circuit_breaker = {
      enable = var.service_config.deployment.circuit_breaker.enable
      rollback = var.service_config.deployment.circuit_breaker.rollback
    }
  }

  # Autoscaling configuration with defaults
  autoscaling = {
    enable_autoscaling = coalesce(
      try(var.service_config.autoscaling.enable_autoscaling, null),
      true
    )
    min_capacity = coalesce(
      try(var.service_config.autoscaling.min_capacity, null),
      0
    )
    max_capacity = coalesce(
      try(var.service_config.autoscaling.max_capacity, null),
      var.service_config.max_autoscale_task_count
    )
    cpu_target_value = coalesce(
      try(var.service_config.autoscaling.cpu_target_value, null),
      70
    )
    memory_target_value = coalesce(
      try(var.service_config.autoscaling.memory_target_value, null),
      80
    )
  }
}

locals {
  suffix = lower(random_id.suffix.hex)
}

resource "random_id" "suffix" {
  byte_length = 2
}

# Security Group for this ECS service
resource "aws_security_group" "this" {
  name_prefix = "${var.app_name}-${var.service_name}-"
  vpc_id      = var.vpc_id

  # Allow traffic from VPC CIDR (for internal communication)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow traffic from ALB security group to application port (when deploying as web app)
  dynamic "ingress" {
    for_each = var.service_config.deploy_as_web_app ? [1] : []
    content {
      from_port       = local.application_port
      to_port         = local.application_port
      protocol        = "tcp"
      security_groups = [var.alb_sg_id]
      description     = "Allow traffic from ALB"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.service_name}"
    Environment = var.environment
    Service     = var.service_name
  }
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
          "arn:aws:ecs:${var.region}:${var.aws_account_id}:cluster/${var.ecs_cluster_name}",
          "arn:aws:ecs:${var.region}:${var.aws_account_id}:cluster/${var.ecs_cluster_name}/*"
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

# S3 policy for ECS tasks
resource "aws_iam_policy" "s3_policy" {
  name = "${var.app_name}-s3-policy-${local.suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

# IAM Role for ECS tasks
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.app_name}-ecs-task-role-${local.suffix}"

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
    Name = "${var.app_name}-ecs-task-role-${local.suffix}"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execute_command_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_execute_command_policy.arn
}

resource "aws_iam_role_policy_attachment" "s3_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# ALB information is passed from parent module

# Route53 hosted zone is passed from parent module

# SSL Certificate for this service
resource "aws_acm_certificate" "this" {
  count = var.service_config.deploy_as_web_app ? 1 : 0

  domain_name       = "openobserve-${lower(var.service_name)}.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name        = "${var.app_name}-${var.service_name}-ssl-cert"
    Environment = var.environment
    Service     = var.service_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = var.service_config.deploy_as_web_app ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# Certificate validation
resource "aws_acm_certificate_validation" "this" {
  count = var.service_config.deploy_as_web_app ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "10m"
  }
  lifecycle {
      ignore_changes = [
          validation_record_fqdns,
      ]
  }
}

# Target Group for ALB (when deploying as web app)
resource "aws_lb_target_group" "this" {
  count = var.service_config.deploy_as_web_app ? 1 : 0

  name        = "${var.app_name}-${var.service_name}-tg-${local.suffix}"
  port        = local.application_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    path                = "/" # TODO: Change to /version
    protocol            = "HTTP"
    port                = local.application_port
    unhealthy_threshold = 10
    timeout             = 10
    matcher             = "200-499"
  }

  tags = {
    Name        = "${var.app_name}-${var.service_name}-tg"
    Environment = var.environment
    Service     = var.service_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Add SSL certificate to ALB listener (after validation completes)
resource "aws_lb_listener_certificate" "this" {
  count = var.service_config.deploy_as_web_app ? 1 : 0

  listener_arn    = var.alb_listener_arn
  certificate_arn = aws_acm_certificate_validation.this[0].certificate_arn

  depends_on = [aws_acm_certificate_validation.this]
}

# ALB Listener Rule for routing traffic to this service
resource "aws_lb_listener_rule" "this" {
  count = var.service_config.deploy_as_web_app ? 1 : 0

  listener_arn = var.alb_listener_arn
  priority     = var.service_config.alb_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  condition {
    host_header {
      values = ["openobserve-${lower(var.service_name)}.${var.domain_name}"]
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.service_name}-listener-rule"
    Environment = var.environment
    Service     = var.service_name
  }

  depends_on = [aws_lb_listener_certificate.this]
}

# CNAME record pointing to ALB DNS for this service
resource "aws_route53_record" "alb_cname" {
  count = var.service_config.deploy_as_web_app ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "openobserve-${lower(var.service_name)}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.alb_dns_name]
}
# SSM Parameters for service-specific environment variables marked as "SSM" (overrides only)
resource "aws_ssm_parameter" "service_secrets" {
  for_each = {
    for key, secret_config in local.service_secrets :
    key => secret_config if secret_config.type == "SSM"
  }

  name = each.value.name
  type = "SecureString"
  # Use the processed value for CONFIG, empty string for others (to be populated manually)
  value = lookup(each.value, "value", "PLACEHOLDER_VALUE_TO_BE_SET_MANUALLY")

  tags = {
    Name        = "${var.app_name}-${var.service_name}-${each.key}"
    Environment = var.environment
    Service     = var.service_name
  }

  lifecycle {
    ignore_changes = [value]
  }

}

# AWS Secrets Manager secrets for service-specific environment variables marked as "SECRET" (overrides only)
resource "aws_secretsmanager_secret" "service_secrets" {
  for_each = toset([
    for key, secret_config in local.service_secrets :
    secret_config.name if secret_config.type == "SECRET"
  ])

  name = each.value

  tags = {
    Name        = "${var.app_name}-secret"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_secretsmanager_secret_version" "service_secrets" {
  for_each = aws_secretsmanager_secret.service_secrets

  secret_id     = each.value.id
  secret_string = "{}" # Empty JSON - to be populated manually later

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.app_name}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.service_config.task_def.vCPU
  memory                   = var.service_config.task_def.vRAM
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  
  runtime_platform {
    cpu_architecture = var.service_config.task_def.cpu_architecture
    operating_system_family = "LINUX"
  }

  
  dynamic "volume" {
    for_each = var.service_config.mount_gp3_volume ? [1] : []
    content {
      name = "gp3-volume"
    }
  }

  container_definitions = jsonencode([
    merge({
      name  = var.service_name
      image = "${var.service_config.repository_name}:${var.service_config.image_tag}"

      command = try(
        # If command is a list, use it directly
        tolist(var.service_config.command),
        # If command is a string, split it by spaces
        split(" ", var.service_config.command),
        # Default to empty list
        []
      )
      workingDirectory = var.service_config.working_dir

      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.service_name
        }
      }

      environment = local.finalized_environment

      secrets = local.finalized_secrets
    }, var.service_config.deploy_as_web_app ? {
      portMappings = [{
        containerPort = local.application_port
        hostPort      = local.application_port
        protocol      = "tcp"
      }]
    } : {}, var.service_config.mount_gp3_volume ? {
      mountPoints = [{
        sourceVolume  = "gp3-volume"
        containerPath = "/data"
        readOnly      = false
      }]
    } : {})
  ])

  tags = {
    Name        = "${var.app_name}-${var.service_name}-task"
    Environment = var.environment
    Service     = var.service_name
  }
}

locals {
  finalized_environment = concat([
    for key, value in local.environment : {
      name  = key
      value = value
    }
  ],
  [
    {
      name = "ZO_NATS_ADDR"
      value = var.nats_url
    },
    {
      name = "ZO_S3_REGION_NAME"
      value = var.region
    },
    {
      name = "ZO_S3_BUCKET_NAME"
      value = var.s3_bucket_name
    }
  ])


  finalized_secrets = concat([
    {
      name = "ZO_META_POSTGRES_DSN"
      valueFrom = "/${var.app_name}/db-service-accounts/${var.database_service_account_name}"
    }
  ], [
    for secret_key, secret_config in local.all_secrets : {
      name = secret_key
      valueFrom = secret_config.type == "SSM" ? secret_config.name : (
        contains(keys(local.service_secrets), secret_key) ?
        aws_secretsmanager_secret.service_secrets[secret_config.name].arn :
        "something_is_wrong"
      )
    }
  ])
}

resource "aws_iam_role_policy_attachment" "ebs_policy" {
  count      = var.service_config.mount_gp3_volume ? 1 : 0
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}


# ECS Service (only if deploy_as_service is true)
resource "aws_ecs_service" "this" {
  count = var.service_config.deploy_as_service ? 1 : 0

  name                   = "${var.app_name}-${var.service_name}-${local.suffix}"
  cluster                = var.ecs_cluster_name
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = var.service_config.task_def.desired_count
  enable_execute_command = true

# Configuration for the volume managed by ECS at launch time
  dynamic "volume_configuration" {
    for_each = var.service_config.mount_gp3_volume ? [1] : []
    content {
      name = "gp3-volume"
      managed_ebs_volume {
        role_arn = aws_iam_role.ecs_task_role.arn
        volume_type      = "gp3"        # General Purpose SSD
        size_in_gb       = 20           # Size of the volume
        file_system_type  = "ext4"       # Filesystem type
        # Optional: retention_policy specifies if the volume is retained or deleted when the task/service is terminated
        # "tag_all" keeps the volume and adds deletion prevention tags
        # "delete" deletes the volume when the task/service is terminated
        # termination_policy = "tag_all"
        # Optional: configure IAM role for volume management if needed
        # volume_lifecycle_goal = "shared" # Not needed for task-managed EBS, the scope is defined by the service
      }
    }
  }

  capacity_provider_strategy {
    capacity_provider = var.service_config.task_def.spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 100
  }

  # Deployment configuration to ensure only 1 task runs during updates
  deployment_minimum_healthy_percent = local.deployment.minimum_healthy_percent
  deployment_maximum_percent         = local.deployment.maximum_percent

  deployment_circuit_breaker {
    enable   = local.deployment.circuit_breaker.enable
    rollback = local.deployment.circuit_breaker.rollback
  }

  network_configuration {
    security_groups  = [aws_security_group.this.id]
    subnets          = var.subnet_ids
    assign_public_ip = false
  }

  # Load balancer configuration (when deploying as web app)
  dynamic "load_balancer" {
    for_each = var.service_config.deploy_as_web_app ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.service_name
      container_port   = local.application_port
    }
  }

  tags = {
    Name             = "${var.app_name}-${var.service_name}-${local.suffix}"
    Environment      = var.environment
    Service          = var.service_name
    OffHoursScaling  = var.enable_off_hours_scaling ? "true" : "false"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_target_group.this, aws_lb_listener_rule.this]
}

resource "aws_ssm_parameter" "ecs_service_arn" {
  name  = "/${var.app_name}/ecs/${var.service_name}/arn"
  type  = "String"
  value = aws_ecs_service.this[0].arn
}

# EventBridge Rule for scheduled service (only if schedule is provided and not deployed as service)
resource "aws_cloudwatch_event_rule" "scheduled" {
  count = !var.service_config.deploy_as_service && var.service_config.schedule != null ? 1 : 0

  name                = "${var.app_name}-${var.service_name}-schedule-${local.suffix}"
  description         = "Scheduled execution for ${var.service_name}"
  schedule_expression = var.service_config.schedule

  tags = {
    Name        = "${var.app_name}-${var.service_name}-schedule-${local.suffix}"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_cloudwatch_event_target" "scheduled" {
  count = !var.service_config.deploy_as_service && var.service_config.schedule != null ? 1 : 0

  rule     = aws_cloudwatch_event_rule.scheduled[0].name
  arn      = local.cluster_arn
  role_arn = var.eventbridge_role_arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.this.arn

    launch_type = "FARGATE"

    network_configuration {
      security_groups  = [aws_security_group.this.id]
      subnets          = var.subnet_ids
      assign_public_ip = false
    }
  }
}

# CloudWatch Log Group for this service
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.app_name}/${var.service_name}-${local.suffix}"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-${var.service_name}-logs-${local.suffix}"
    Environment = var.environment
    Service     = var.service_name
  }
}

# Construct cluster ARN for EventBridge targets
locals {
  cluster_arn = "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:cluster/${var.ecs_cluster_name}"
}

# Auto Scaling for ECS Service (only if autoscaling is enabled and deployed as service)
resource "aws_appautoscaling_target" "this" {
  count = local.autoscaling.enable_autoscaling && var.service_config.deploy_as_service ? 1 : 0

  max_capacity       = local.autoscaling.max_capacity
  min_capacity       = local.autoscaling.min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.this[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = local.autoscaling.enable_autoscaling && var.service_config.deploy_as_service ? 1 : 0

  name               = "${var.app_name}-${var.service_name}-cpu-scaling-${local.suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = local.autoscaling.cpu_target_value
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = local.autoscaling.enable_autoscaling && var.service_config.deploy_as_service ? 1 : 0

  name               = "${var.app_name}-${var.service_name}-memory-scaling-${local.suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = local.autoscaling.memory_target_value
  }
}
