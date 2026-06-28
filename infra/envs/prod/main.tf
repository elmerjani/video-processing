locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = "prod"
      ManagedBy   = "terraform"
    },
    var.tags
  )
  ecs_subnet_ids   = var.ecs_assign_public_ip ? module.vpc.public_subnet_ids : module.vpc.private_subnet_ids
  ecs_subnet_cidrs = var.ecs_assign_public_ip ? module.vpc.public_subnet_cidrs : module.vpc.private_subnet_cidrs
  api_image        = coalesce(var.api_image, "${module.ecr.api_repository_url}:${var.image_tag}")
  worker_image     = coalesce(var.worker_image, "${module.ecr.worker_repository_url}:${var.image_tag}")
}

module "vpc" {
  source = "../../modules/vpc"

  name               = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  name                        = var.project_name
  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnet_ids
  subnet_ids                  = module.vpc.private_subnet_ids
  internal                    = true
  allowed_ingress_cidr_blocks = []
  container_port              = var.container_port
  tags                        = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  name                = "${var.project_name}-users"
  deletion_protection = true
  tags                = local.common_tags
}

module "api_gateway" {
  source = "../../modules/api_gateway"

  name                   = "${var.project_name}-api"
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  alb_listener_arn       = module.alb.listener_arn
  alb_security_group_id  = module.alb.security_group_id
  jwt_issuer             = module.cognito.issuer_uri
  jwt_audience           = module.cognito.client_id
  stage_name             = var.api_gateway_stage_name
  log_retention_in_days  = var.api_gateway_log_retention_in_days
  throttling_burst_limit = var.api_gateway_throttling_burst_limit
  throttling_rate_limit  = var.api_gateway_throttling_rate_limit
  tags                   = local.common_tags
}

module "waf" {
  count  = var.enable_waf ? 1 : 0
  source = "../../modules/waf"

  name         = "${var.project_name}-web-acl"
  resource_arn = module.alb.load_balancer_arn
  rate_limit   = var.waf_rate_limit
  tags         = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  name            = var.project_name
  max_image_count = var.ecr_max_image_count
  force_delete    = var.ecr_force_delete
  tags            = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  name              = var.project_name
  enable_versioning = var.s3_enable_versioning
  force_destroy     = var.s3_force_destroy
  tags              = local.common_tags
}

module "sqs" {
  source = "../../modules/sqs"

  name                       = var.project_name
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  receive_wait_time_seconds  = var.sqs_receive_wait_time_seconds
  max_receive_count          = var.sqs_max_receive_count
  tags                       = local.common_tags
}

module "vpc_endpoints" {
  source = "../../modules/vpc_endpoints"

  name                    = var.project_name
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  allowed_security_group_ids = [
    module.ecs.task_security_group_id,
    module.upload_notification.upload_handler_security_group_id,
  ]
  tags = local.common_tags
}

module "upload_notification" {
  source = "../../modules/s3_upload_notification"

  name                  = var.project_name
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  bucket_name           = module.s3.bucket_name
  bucket_arn            = module.s3.bucket_arn
  queue_url             = module.sqs.queue_url
  queue_arn             = module.sqs.queue_arn
  database_secret_arn   = module.rds.database_secret_arn
  database_host         = module.rds.address
  database_port         = module.rds.port
  database_name         = var.database_name
  database_sslmode      = var.database_sslmode
  log_retention_in_days = var.cloudwatch_retention_in_days
  upload_prefix         = "uploads/"
  tags                  = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  name                = var.project_name
  video_bucket_arn    = module.s3.bucket_arn
  jobs_queue_arn      = module.sqs.queue_arn
  database_secret_arn = module.rds.database_secret_arn
  tags                = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  name                    = var.project_name
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  allowed_cidr_blocks     = []
  database_name           = var.database_name
  database_username       = var.database_username
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  max_allocated_storage   = var.db_max_allocated_storage
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  multi_az                = var.db_multi_az
  tags                    = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.ecs.task_security_group_id
  description                  = "PostgreSQL from ECS tasks"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_upload_handler" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.upload_notification.upload_handler_security_group_id
  description                  = "PostgreSQL from upload-handler Lambda"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = try(trimspace(var.alarm_notification_email), "") != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name                     = var.project_name
  jobs_queue_name          = module.sqs.queue_name
  jobs_dlq_name            = module.sqs.dlq_name
  upload_handler_dlq_name  = module.upload_notification.upload_handler_dlq_name
  database_identifier      = module.rds.identifier
  load_balancer_arn_suffix = module.alb.load_balancer_arn_suffix
  target_group_arn_suffix  = module.alb.target_group_arn_suffix
  retention_in_days        = var.cloudwatch_retention_in_days
  create_metric_alarms     = var.create_cloudwatch_metric_alarms
  alarm_action_arns        = [aws_sns_topic.alerts.arn]
  tags                     = local.common_tags
}

module "ecs" {
  source = "../../modules/ecs"

  name                                            = var.project_name
  aws_region                                      = var.aws_region
  vpc_id                                          = module.vpc.vpc_id
  subnet_ids                                      = local.ecs_subnet_ids
  assign_public_ip                                = var.ecs_assign_public_ip
  alb_security_group_id                           = module.alb.security_group_id
  target_group_arn                                = module.alb.target_group_arn
  execution_role_arn                              = module.iam.execution_role_arn
  api_task_role_arn                               = module.iam.api_task_role_arn
  worker_task_role_arn                            = module.iam.worker_task_role_arn
  api_image                                       = local.api_image
  worker_image                                    = local.worker_image
  container_port                                  = var.container_port
  api_cpu                                         = var.api_cpu
  api_memory                                      = var.api_memory
  worker_cpu                                      = var.worker_cpu
  worker_memory                                   = var.worker_memory
  api_desired_count                               = var.api_desired_count
  worker_desired_count                            = var.worker_desired_count
  worker_visibility_timeout_seconds               = var.worker_visibility_timeout_seconds
  worker_max_receive_count                        = var.worker_max_receive_count
  worker_autoscaling_enabled                      = var.worker_autoscaling_enabled
  worker_autoscaling_min_capacity                 = var.worker_autoscaling_min_capacity
  worker_autoscaling_max_capacity                 = var.worker_autoscaling_max_capacity
  worker_autoscaling_scale_out_threshold          = var.worker_autoscaling_scale_out_threshold
  worker_autoscaling_scale_in_threshold           = var.worker_autoscaling_scale_in_threshold
  worker_autoscaling_alarm_period                 = var.worker_autoscaling_alarm_period
  worker_autoscaling_scale_out_evaluation_periods = var.worker_autoscaling_scale_out_evaluation_periods
  worker_autoscaling_scale_in_evaluation_periods  = var.worker_autoscaling_scale_in_evaluation_periods
  worker_autoscaling_scale_in_cooldown            = var.worker_autoscaling_scale_in_cooldown
  worker_autoscaling_scale_out_cooldown           = var.worker_autoscaling_scale_out_cooldown
  capacity_provider                               = var.ecs_capacity_provider
  container_insights_enabled                      = var.container_insights_enabled
  deployment_circuit_breaker_enabled              = var.deployment_circuit_breaker_enabled
  video_bucket_name                               = module.s3.bucket_name
  jobs_queue_url                                  = module.sqs.queue_url
  jobs_queue_name                                 = module.sqs.queue_name
  database_secret_arn                             = module.rds.database_secret_arn
  database_host                                   = module.rds.address
  database_port                                   = module.rds.port
  database_name                                   = var.database_name
  cognito_issuer_uri                              = module.cognito.issuer_uri
  cognito_client_id                               = module.cognito.client_id
  api_log_group_name                              = module.cloudwatch.api_log_group_name
  worker_log_group_name                           = module.cloudwatch.worker_log_group_name
  tags                                            = local.common_tags
}

resource "aws_codestarconnections_connection" "github" {
  count = var.enable_api_pipeline || var.enable_worker_pipeline ? 1 : 0

  name          = "${var.project_name}-github"
  provider_type = "GitHub"
  tags          = local.common_tags
}

module "api_pipeline" {
  count  = var.enable_api_pipeline ? 1 : 0
  source = "../../modules/image_pipeline"

  project_name                  = var.api_pipeline_project_name
  codestar_connection_arn       = aws_codestarconnections_connection.github[0].arn
  github_owner                  = coalesce(var.api_pipeline_github_owner, "unset")
  github_repository             = coalesce(var.api_pipeline_github_repository, "unset")
  github_branch                 = var.api_pipeline_github_branch
  buildspec_path                = var.api_pipeline_buildspec_path
  source_directory              = "api"
  build_compute_type            = var.api_pipeline_build_compute_type
  log_retention_in_days         = var.api_pipeline_log_retention_in_days
  artifact_bucket_force_destroy = var.pipeline_artifact_bucket_force_destroy
  ecr_repository_url            = module.ecr.api_repository_url
  ecr_repository_arn            = module.ecr.api_repository_arn
  ecs_cluster_name              = module.ecs.cluster_name
  ecs_service_name              = module.ecs.api_service_name
  ecs_execution_role_arn        = module.iam.execution_role_arn
  ecs_task_role_arn             = module.iam.api_task_role_arn
  container_name                = "api"
  deploy_action_name            = "DeployApi"
  tags                          = local.common_tags
}

module "worker_pipeline" {
  count  = var.enable_worker_pipeline ? 1 : 0
  source = "../../modules/image_pipeline"

  project_name                  = var.worker_pipeline_project_name
  codestar_connection_arn       = aws_codestarconnections_connection.github[0].arn
  github_owner                  = coalesce(var.worker_pipeline_github_owner, "unset")
  github_repository             = coalesce(var.worker_pipeline_github_repository, "unset")
  github_branch                 = var.worker_pipeline_github_branch
  buildspec_path                = var.worker_pipeline_buildspec_path
  source_directory              = "worker"
  build_compute_type            = var.worker_pipeline_build_compute_type
  log_retention_in_days         = var.worker_pipeline_log_retention_in_days
  artifact_bucket_force_destroy = var.pipeline_artifact_bucket_force_destroy
  ecr_repository_url            = module.ecr.worker_repository_url
  ecr_repository_arn            = module.ecr.worker_repository_arn
  ecs_cluster_name              = module.ecs.cluster_name
  ecs_service_name              = module.ecs.worker_service_name
  ecs_execution_role_arn        = module.iam.execution_role_arn
  ecs_task_role_arn             = module.iam.worker_task_role_arn
  container_name                = "worker"
  deploy_action_name            = "DeployWorker"
  tags                          = local.common_tags
}

check "api_pipeline_required_values" {
  assert {
    condition = !var.enable_api_pipeline || alltrue([
      var.api_pipeline_github_owner != null,
      var.api_pipeline_github_repository != null,
    ])
    error_message = "When enable_api_pipeline is true, set api_pipeline_github_owner and api_pipeline_github_repository."
  }
}

check "worker_pipeline_required_values" {
  assert {
    condition = !var.enable_worker_pipeline || alltrue([
      var.worker_pipeline_github_owner != null,
      var.worker_pipeline_github_repository != null,
    ])
    error_message = "When enable_worker_pipeline is true, set worker_pipeline_github_owner and worker_pipeline_github_repository."
  }
}
