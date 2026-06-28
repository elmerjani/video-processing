output "upload_handler_lambda_name" {
  value = module.upload_handler.function_name
}

output "upload_handler_dlq_url" {
  value = module.upload_handler.failure_dlq_url
}

output "upload_handler_dlq_name" {
  value = module.upload_handler.failure_dlq_name
}

output "upload_handler_security_group_id" {
  value = module.upload_handler.security_group_id
}
