
resource "aws_security_group" "nats" {
  name        = "${var.app_name}-nats-sg"
  description = "Security group for NATS ECS tasks"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 4222
    to_port     = 4222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # NATS clustering port - allow communication between NATS instances
  ingress {
    from_port       = 6222
    to_port         = 6222
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description     = "NATS cluster communication"
  }
  # NATS monitoring, enable if needed (add your ip for cidr blocks to prevent outside access)
  # ingress {
  #   from_port   = 8222
  #   to_port     = 8222
  #   protocol    = "tcp"
  #   cidr_blocks = ["1.2.3.4/32"]
  #   description = "Admin / monitoring"
  # }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "nats" {
  name              = "/ecs/${var.app_name}/nats"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "nats" {
  family                   = "${var.app_name}-nats"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn

  runtime_platform {
    cpu_architecture = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "nats"
      image     = var.image
      essential = true
      portMappings = [
        { containerPort = 4222, hostPort = 4222, protocol = "tcp" },
        { containerPort = 6222, hostPort = 6222, protocol = "tcp" },
        { containerPort = 8222, hostPort = 8222, protocol = "tcp" }
      ]
      command = ["sh", "-c", "exec nats-server -js --http_port=8222 --server_name=nats-server-$${HOSTNAME} --cluster_name=${var.app_name}-nats-cluster --cluster=nats://0.0.0.0:6222 --routes=nats://${var.app_name}-nats.${var.app_name}.local:6222"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.nats.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nats"
        }
      }
    }
  ])

  tags = {
    Name       = "${var.app_name}-nats"
    Environment = var.env
  }
}

resource "aws_service_discovery_service" "nats" {
  name = "${var.app_name}-nats"
  dns_config {
    namespace_id   = var.service_discovery_namespace_id
    routing_policy = "MULTIVALUE"
    
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
  tags = {
    Name        = "${var.app_name}-nats-service"
    Environment = var.env
  }
}

resource "aws_ecs_service" "nats" {
  name            = "nats"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.nats.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = true
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.nats.id]
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.nats.arn
    container_name = "nats"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}