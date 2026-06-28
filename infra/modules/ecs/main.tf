resource "aws_security_group" "tasks" {
  name        = "${var.name}-ecs-tasks"
  description = "Allow ALB to reach API tasks and tasks to call AWS services"
  vpc_id      = var.vpc_id

  ingress {
    description     = "API from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ecs-tasks-sg" })
}

resource "aws_ecs_cluster" "main" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.api_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = var.api_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "VIDEO_BUCKET", value = var.video_bucket_name },
        { name = "DATABASE_SECRET_ARN", value = var.database_secret_arn },
        { name = "DATABASE_HOST", value = var.database_host },
        { name = "DATABASE_PORT", value = tostring(var.database_port) },
        { name = "DATABASE_NAME", value = var.database_name },
        { name = "DATABASE_SSLMODE", value = var.database_sslmode },
        { name = "COGNITO_ISSUER_URI", value = var.cognito_issuer_uri },
        { name = "COGNITO_CLIENT_ID", value = var.cognito_client_id }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.api_log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.worker_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = var.worker_image
      essential = true
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "VIDEO_BUCKET", value = var.video_bucket_name },
        { name = "VIDEO_JOBS_QUEUE_URL", value = var.jobs_queue_url },
        { name = "DATABASE_SECRET_ARN", value = var.database_secret_arn },
        { name = "DATABASE_HOST", value = var.database_host },
        { name = "DATABASE_PORT", value = tostring(var.database_port) },
        { name = "DATABASE_NAME", value = var.database_name },
        { name = "DATABASE_SSLMODE", value = var.database_sslmode },
        { name = "WORKER_VISIBILITY_TIMEOUT_SECONDS", value = tostring(var.worker_visibility_timeout_seconds) },
        { name = "WORKER_MAX_RECEIVE_COUNT", value = tostring(var.worker_max_receive_count) }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.worker_log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "worker"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "api" {
  name                              = "${var.name}-api"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.api_desired_count
  health_check_grace_period_seconds = var.api_health_check_grace_period_seconds

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker_enabled ? [1] : []

    content {
      enable   = true
      rollback = true
    }
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "api"
    container_port   = var.container_port
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]

  tags = var.tags
}

resource "aws_ecs_service" "worker" {
  name            = "${var.name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_autoscaling_enabled ? var.worker_autoscaling_min_capacity : var.worker_desired_count

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker_enabled ? [1] : []

    content {
      enable   = true
      rollback = true
    }
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.tags
}

resource "aws_appautoscaling_target" "worker" {
  count = var.worker_autoscaling_enabled ? 1 : 0

  max_capacity       = var.worker_autoscaling_max_capacity
  min_capacity       = var.worker_autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_scale_out" {
  count = var.worker_autoscaling_enabled ? 1 : 0

  name               = "${var.name}-worker-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.worker_autoscaling_scale_out_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "worker_scale_in" {
  count = var.worker_autoscaling_enabled ? 1 : 0

  name               = "${var.name}-worker-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.worker_autoscaling_scale_in_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "worker_visible_messages_high" {
  count = var.worker_autoscaling_enabled ? 1 : 0

  alarm_name          = "${var.name}-worker-visible-messages-high"
  alarm_description   = "Scale out worker service when SQS has visible jobs waiting."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.worker_autoscaling_scale_out_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.worker_autoscaling_alarm_period
  statistic           = "Average"
  threshold           = var.worker_autoscaling_scale_out_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.worker_scale_out[0].arn]

  dimensions = {
    QueueName = var.jobs_queue_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "worker_queue_empty" {
  count = var.worker_autoscaling_enabled ? 1 : 0

  alarm_name          = "${var.name}-worker-queue-empty"
  alarm_description   = "Scale in worker service only when SQS has no visible or in-flight jobs."
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = var.worker_autoscaling_scale_in_evaluation_periods
  threshold           = var.worker_autoscaling_scale_in_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.worker_scale_in[0].arn]

  metric_query {
    id          = "backlog"
    expression  = "visible + notvisible"
    label       = "Visible plus in-flight SQS messages"
    return_data = true
  }

  metric_query {
    id = "visible"

    metric {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      period      = var.worker_autoscaling_alarm_period
      stat        = "Average"

      dimensions = {
        QueueName = var.jobs_queue_name
      }
    }
  }

  metric_query {
    id = "notvisible"

    metric {
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      namespace   = "AWS/SQS"
      period      = var.worker_autoscaling_alarm_period
      stat        = "Average"

      dimensions = {
        QueueName = var.jobs_queue_name
      }
    }
  }

  tags = var.tags
}
