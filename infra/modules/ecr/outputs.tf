output "api_repository_url" { value = aws_ecr_repository.api.repository_url }
output "api_repository_name" { value = aws_ecr_repository.api.name }
output "api_repository_arn" { value = aws_ecr_repository.api.arn }
output "worker_repository_url" { value = aws_ecr_repository.worker.repository_url }
output "worker_repository_name" { value = aws_ecr_repository.worker.name }
output "worker_repository_arn" { value = aws_ecr_repository.worker.arn }
