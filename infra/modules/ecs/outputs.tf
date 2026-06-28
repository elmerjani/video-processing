output "task_security_group_id" { value = aws_security_group.tasks.id }
output "cluster_name" { value = aws_ecs_cluster.main.name }
output "api_service_name" { value = aws_ecs_service.api.name }
output "worker_service_name" { value = aws_ecs_service.worker.name }
