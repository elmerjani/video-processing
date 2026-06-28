output "api_load_balancer_dns_name" {
  value = module.alb.dns_name
}

output "api_gateway_invoke_url" {
  value = module.api_gateway.invoke_url
}

output "cognito_user_pool_id" { value = module.cognito.user_pool_id }
output "cognito_client_id" { value = module.cognito.client_id }

output "api_ecr_repository_url" {
  value = module.ecr.api_repository_url
}

output "worker_ecr_repository_url" {
  value = module.ecr.worker_repository_url
}

output "video_bucket_name" {
  value = module.s3.bucket_name
}

output "video_jobs_queue_url" {
  value = module.sqs.queue_url
}

output "video_jobs_dlq_url" {
  value = module.sqs.dlq_url
}

output "database_endpoint" {
  value = module.rds.endpoint
}

output "database_secret_arn" {
  value = module.rds.database_secret_arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "api_ecs_service_name" {
  value = module.ecs.api_service_name
}

output "worker_ecs_service_name" {
  value = module.ecs.worker_service_name
}

output "api_pipeline_name" {
  value = try(module.api_pipeline[0].pipeline_name, null)
}

output "worker_pipeline_name" {
  value = try(module.worker_pipeline[0].pipeline_name, null)
}

output "github_connection_arn" {
  value = try(aws_codestarconnections_connection.github[0].arn, null)
}
