variable "name" { type = string }
variable "jobs_queue_name" { type = string }
variable "jobs_dlq_name" { type = string }
variable "upload_handler_dlq_name" { type = string }
variable "database_identifier" { type = string }
variable "load_balancer_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "retention_in_days" {
  type    = number
  default = 14
}
variable "create_metric_alarms" {
  type    = bool
  default = false
}
variable "alarm_action_arns" {
  type    = list(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
