variable "project_name" {
  type    = string
  default = "video-processing-dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = []
}

variable "api_gateway_stage_name" {
  type    = string
  default = "dev"
}

variable "api_gateway_log_retention_in_days" {
  type    = number
  default = 1
}

variable "api_gateway_throttling_burst_limit" {
  type    = number
  default = 100
}

variable "api_gateway_throttling_rate_limit" {
  type    = number
  default = 50
}

variable "enable_waf" {
  type    = bool
  default = true
}

variable "waf_rate_limit" {
  type    = number
  default = 1000
}

variable "api_image" {
  type    = string
  default = null
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "worker_image" {
  type    = string
  default = null
}

variable "database_name" {
  type    = string
  default = "videoprocessing"
}

variable "database_username" {
  type    = string
  default = "video_app"
}

variable "database_sslmode" {
  type    = string
  default = "require"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  type    = number
  default = null
}

variable "db_backup_retention_period" {
  type    = number
  default = 0
}

variable "api_cpu" {
  type    = number
  default = 256
}

variable "api_memory" {
  type    = number
  default = 512
}

variable "worker_cpu" {
  type    = number
  default = 256
}

variable "worker_memory" {
  type    = number
  default = 512
}

variable "api_desired_count" {
  type    = number
  default = 1
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

variable "worker_visibility_timeout_seconds" {
  type    = number
  default = 3600
}

variable "worker_max_receive_count" {
  type    = number
  default = 3
}

variable "worker_autoscaling_enabled" {
  type    = bool
  default = true
}

variable "worker_autoscaling_min_capacity" {
  type    = number
  default = 1
}

variable "worker_autoscaling_max_capacity" {
  type    = number
  default = 5
}

variable "worker_autoscaling_scale_out_threshold" {
  type    = number
  default = 1
}

variable "worker_autoscaling_scale_in_threshold" {
  type    = number
  default = 0
}

variable "worker_autoscaling_alarm_period" {
  type    = number
  default = 60
}

variable "worker_autoscaling_scale_out_evaluation_periods" {
  type    = number
  default = 1
}

variable "worker_autoscaling_scale_in_evaluation_periods" {
  type    = number
  default = 10
}

variable "worker_autoscaling_scale_in_cooldown" {
  type    = number
  default = 600
}

variable "worker_autoscaling_scale_out_cooldown" {
  type    = number
  default = 60
}

variable "ecs_assign_public_ip" {
  type    = bool
  default = false
}

variable "ecs_capacity_provider" {
  type    = string
  default = "FARGATE_SPOT"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.ecs_capacity_provider)
    error_message = "ecs_capacity_provider must be either FARGATE or FARGATE_SPOT."
  }
}

variable "container_insights_enabled" {
  type    = bool
  default = false
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cloudwatch_retention_in_days" {
  type    = number
  default = 1
}

variable "create_cloudwatch_metric_alarms" {
  type    = bool
  default = false
}

variable "s3_enable_versioning" {
  type    = bool
  default = false
}

variable "s3_force_destroy" {
  type    = bool
  default = true
}

variable "ecr_max_image_count" {
  type    = number
  default = 5
}

variable "ecr_force_delete" {
  type    = bool
  default = true
}

variable "pipeline_artifact_bucket_force_destroy" {
  type    = bool
  default = true
}

variable "sqs_visibility_timeout_seconds" {
  type    = number
  default = 3600
}

variable "sqs_message_retention_seconds" {
  type    = number
  default = 345600
}

variable "sqs_receive_wait_time_seconds" {
  type    = number
  default = 20
}

variable "sqs_max_receive_count" {
  type    = number
  default = 3
}

variable "enable_api_pipeline" {
  type    = bool
  default = false
}

variable "api_pipeline_project_name" {
  type    = string
  default = "video-processing-dev-api"
}

variable "api_pipeline_github_owner" {
  type     = string
  default  = null
  nullable = true
}

variable "api_pipeline_github_repository" {
  type     = string
  default  = null
  nullable = true
}

variable "api_pipeline_github_branch" {
  type    = string
  default = "main"
}

variable "api_pipeline_buildspec_path" {
  type    = string
  default = "api/buildspec.yml"
}

variable "api_pipeline_build_compute_type" {
  type    = string
  default = "BUILD_GENERAL1_SMALL"
}

variable "api_pipeline_log_retention_in_days" {
  type    = number
  default = 1
}

variable "enable_worker_pipeline" {
  type    = bool
  default = false
}

variable "worker_pipeline_project_name" {
  type    = string
  default = "video-processing-dev-worker"
}

variable "worker_pipeline_github_owner" {
  type     = string
  default  = null
  nullable = true
}

variable "worker_pipeline_github_repository" {
  type     = string
  default  = null
  nullable = true
}

variable "worker_pipeline_github_branch" {
  type    = string
  default = "main"
}

variable "worker_pipeline_buildspec_path" {
  type    = string
  default = "worker/buildspec.yml"
}

variable "worker_pipeline_build_compute_type" {
  type    = string
  default = "BUILD_GENERAL1_SMALL"
}

variable "worker_pipeline_log_retention_in_days" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
