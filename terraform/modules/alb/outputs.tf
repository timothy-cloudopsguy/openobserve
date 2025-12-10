output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.public_alb.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.public_alb.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = aws_lb.public_alb.zone_id
}

output "security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb_sg.id
}

output "https_listener_arn" {
  description = "HTTPS listener ARN"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}
