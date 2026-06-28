resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name}/api"
  retention_in_days = var.retention_in_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.name}/worker"
  retention_in_days = var.retention_in_days
  tags              = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_visible_messages" {
  count = var.create_metric_alarms ? 1 : 0

  alarm_name          = "${var.name}-dlq-visible-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages are present in the video processing DLQ."
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns

  dimensions = {
    QueueName = var.jobs_dlq_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "worker_queue_depth" {
  count = var.create_metric_alarms ? 1 : 0

  alarm_name          = "${var.name}-worker-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "The video job queue is backing up."
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns

  dimensions = {
    QueueName = var.jobs_queue_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  count = var.create_metric_alarms ? 1 : 0

  alarm_name          = "${var.name}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "API target is returning 5xx responses."
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "upload_handler_dlq_visible_messages" {
  count = var.create_metric_alarms ? 1 : 0

  alarm_name          = "${var.name}-upload-handler-dlq-visible-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages are present in the upload-handler Lambda DLQ."
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns

  dimensions = {
    QueueName = var.upload_handler_dlq_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.create_metric_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU has exceeded 80 percent for 15 minutes."
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns

  dimensions = {
    DBInstanceIdentifier = var.database_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  count = var.create_metric_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648
  alarm_description   = "RDS free storage is below 2 GiB."
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns

  dimensions = {
    DBInstanceIdentifier = var.database_identifier
  }

  tags = var.tags
}
