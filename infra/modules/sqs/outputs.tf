output "queue_url" { value = aws_sqs_queue.video_jobs.url }
output "queue_arn" { value = aws_sqs_queue.video_jobs.arn }
output "queue_name" { value = aws_sqs_queue.video_jobs.name }
output "dlq_url" { value = aws_sqs_queue.video_jobs_dlq.url }
output "dlq_arn" { value = aws_sqs_queue.video_jobs_dlq.arn }
output "dlq_name" { value = aws_sqs_queue.video_jobs_dlq.name }
