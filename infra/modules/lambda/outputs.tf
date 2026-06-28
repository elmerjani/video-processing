output "function_name" { value = aws_lambda_function.this.function_name }
output "function_arn" { value = aws_lambda_function.this.arn }
output "role_arn" { value = aws_iam_role.this.arn }
output "security_group_id" { value = aws_security_group.this.id }
output "failure_dlq_url" { value = aws_sqs_queue.failures.url }
output "failure_dlq_arn" { value = aws_sqs_queue.failures.arn }
output "failure_dlq_name" { value = aws_sqs_queue.failures.name }
