variable "project_name" {
  type = string
}

variable "codestar_connection_arn" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repository" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "buildspec_path" {
  type    = string
  default = "buildspec.yml"
}

variable "source_directory" {
  description = "Repository-relative directory containing the component Dockerfile and source code."
  type        = string

  validation {
    condition     = length(trim(var.source_directory, "/")) > 0 && var.source_directory == trim(var.source_directory, "/")
    error_message = "source_directory must be a non-empty repository-relative path without leading or trailing slashes."
  }
}

variable "build_image" {
  type    = string
  default = "aws/codebuild/standard:7.0"
}

variable "build_compute_type" {
  type    = string
  default = "BUILD_GENERAL1_SMALL"
}

variable "log_retention_in_days" {
  type    = number
  default = 1
}

variable "artifact_bucket_force_destroy" {
  type    = bool
  default = false
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "ecs_execution_role_arn" {
  type = string
}

variable "ecs_task_role_arn" {
  type = string
}

variable "container_name" {
  type    = string
  default = "api"
}

variable "deploy_action_name" {
  type    = string
  default = "DeployImage"
}

variable "tags" {
  type    = map(string)
  default = {}
}
