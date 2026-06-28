variable "name" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "assign_public_ip" {
  type    = bool
  default = false
}
variable "alb_security_group_id" { type = string }
variable "target_group_arn" { type = string }
variable "execution_role_arn" { type = string }
variable "api_task_role_arn" { type = string }
variable "worker_task_role_arn" { type = string }
variable "api_image" { type = string }
variable "worker_image" { type = string }
variable "container_port" { type = number }
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
variable "api_desired_count" { type = number }
variable "api_health_check_grace_period_seconds" {
  type    = number
  default = 180
}
variable "worker_desired_count" { type = number }
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
  default = 3
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
variable "capacity_provider" {
  type    = string
  default = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.capacity_provider)
    error_message = "capacity_provider must be either FARGATE or FARGATE_SPOT."
  }
}
variable "container_insights_enabled" {
  type    = bool
  default = false
}
variable "deployment_circuit_breaker_enabled" {
  type    = bool
  default = false
}
variable "video_bucket_name" { type = string }
variable "jobs_queue_url" { type = string }
variable "jobs_queue_name" { type = string }
variable "database_secret_arn" { type = string }
variable "database_host" { type = string }
variable "database_port" { type = number }
variable "database_name" { type = string }
variable "database_sslmode" {
  type    = string
  default = "require"
}
variable "cognito_issuer_uri" { type = string }
variable "cognito_client_id" { type = string }
variable "api_log_group_name" { type = string }
variable "worker_log_group_name" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
