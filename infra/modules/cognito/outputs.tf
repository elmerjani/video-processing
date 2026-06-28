output "user_pool_id" { value = aws_cognito_user_pool.this.id }
output "client_id" { value = aws_cognito_user_pool_client.this.id }
output "issuer_uri" { value = "https://${aws_cognito_user_pool.this.endpoint}" }
output "user_pool_arn" { value = aws_cognito_user_pool.this.arn }
