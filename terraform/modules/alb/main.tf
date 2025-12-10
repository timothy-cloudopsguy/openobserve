# Security group for ALB
resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.app_name}-${var.env_name}-alb-"
  vpc_id      = var.vpc_id

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-${var.env_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "public_alb" {
  name               = "${var.app_name}-${var.env_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.app_name}-${var.env_name}-alb"
  }
}

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener (only created if certificates exist)
resource "aws_lb_listener" "https" {
  count = length(aws_acm_certificate.alb_certs) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.public_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = element([for cert in aws_acm_certificate.alb_certs : cert.arn], 0)

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "ALB is running"
      status_code  = "200"
    }
  }
}

# Get Route53 hosted zones for certificate validation
data "aws_route53_zone" "hosted_zones" {
  for_each = toset(var.route53_hosted_zones.base_fqdns)

  name = each.value
}

# ACM Certificates for HTTPS (one per base_fqdn)
resource "aws_acm_certificate" "alb_certs" {
  for_each = toset(var.route53_hosted_zones.base_fqdns)

  domain_name       = each.value
  validation_method = "DNS"

  tags = {
    Name = "${var.app_name}-${var.env_name}-alb-cert-${each.value}"
  }
}

# Certificate validation records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in flatten([
      for cert_key, cert in aws_acm_certificate.alb_certs : [
        for dvo in cert.domain_validation_options : {
          cert_key = cert_key
          dvo      = dvo
        }
      ]
    ]) : "${dvo.cert_key}-${dvo.dvo.domain_name}" => dvo
  }

  zone_id = data.aws_route53_zone.hosted_zones[each.value.cert_key].zone_id
  name    = each.value.dvo.resource_record_name
  type    = each.value.dvo.resource_record_type
  records = [each.value.dvo.resource_record_value]
  ttl     = 60
}

# Certificate validation
resource "aws_acm_certificate_validation" "cert_validation" {
  for_each = aws_acm_certificate.alb_certs

  certificate_arn         = each.value.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn if startswith(record.name, each.key)]
}

# SSM Parameter for ALB ARN
resource "aws_ssm_parameter" "alb_arn" {
  name  = "/${var.app_name}/alb/${var.env_name}/arn"
  type  = "String"
  value = aws_lb.public_alb.arn
}


resource "aws_ssm_parameter" "alb_dns_name" {
  name  = "/${var.app_name}/alb/${var.env_name}/dns-name"
  type  = "String"
  value = aws_lb.public_alb.dns_name
}

resource "aws_ssm_parameter" "alb_sg_id" {
  name  = "/${var.app_name}/alb/${var.env_name}/sg-id"
  type  = "String"
  value = aws_security_group.alb_sg.id
}

resource "aws_ssm_parameter" "alb_listener_arn" {
  count = length(aws_lb_listener.https) > 0 ? 1 : 0

  name  = "/${var.app_name}/alb/${var.env_name}/listener-arn"
  type  = "String"
  value = aws_lb_listener.https[0].arn
}