variable "name" { type = string }
variable "runtime" {
  type    = string
  default = "python3.12"

  validation {
    condition     = startswith(var.runtime, "python")
    error_message = "The lambda module currently packages Python runtimes only."
  }
}
variable "handler" {
  type    = string
  default = "handler.lambda_handler"
}
variable "architecture" {
  type    = string
  default = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}
variable "source_file" { type = string }
variable "requirements_file" { type = string }
variable "environment_variables" {
  type    = map(string)
  default = {}
}
variable "application_policy_json" {
  type    = string
  default = null
}
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "timeout" {
  type    = number
  default = 30
}
variable "memory_size" {
  type    = number
  default = 256
}
variable "log_retention_in_days" {
  type    = number
  default = 7
}
variable "maximum_event_age_in_seconds" {
  type    = number
  default = 21600
}
variable "maximum_retry_attempts" {
  type    = number
  default = 2
}
variable "tags" {
  type    = map(string)
  default = {}
}
