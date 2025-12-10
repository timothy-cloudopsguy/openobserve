output "service_account_name" {
  description = "Name of the created service account"
  value       = var.service_account_name
}

output "ssm_parameter_name" {
  description = "SSM parameter containing the service account credentials"
  value       = var.ssm_parameter_name
}

output "lambda_function_name" {
  description = "Name of the Lambda function that manages the service account"
  value       = aws_lambda_function.db_service_account.function_name
}

output "lambda_invocation_result" {
  description = "Result of the Lambda invocation"
  value       = jsondecode(aws_lambda_invocation.create_service_account.result)
}
