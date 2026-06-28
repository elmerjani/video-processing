resource "aws_sqs_queue" "video_jobs_dlq" {
  name                      = "${var.name}-jobs-dlq"
  message_retention_seconds = 1209600

  tags = var.tags
}

resource "aws_sqs_queue" "video_jobs" {
  name                       = "${var.name}-jobs"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_jobs_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}
