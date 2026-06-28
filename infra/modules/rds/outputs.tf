output "address" { value = aws_db_instance.postgres.address }
output "endpoint" { value = aws_db_instance.postgres.endpoint }
output "port" { value = aws_db_instance.postgres.port }
output "database_secret_arn" { value = aws_db_instance.postgres.master_user_secret[0].secret_arn }
output "security_group_id" { value = aws_security_group.rds.id }
output "identifier" { value = aws_db_instance.postgres.identifier }
