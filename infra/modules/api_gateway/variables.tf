variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "alb_listener_arn" { type = string }
variable "alb_security_group_id" { type = string }
variable "stage_name" { type = string }
variable "jwt_issuer" { type = string }
variable "jwt_audience" { type = string }
variable "log_retention_in_days" {
  type    = number
  default = 7
}
variable "throttling_burst_limit" {
  type    = number
  default = 100
}
variable "throttling_rate_limit" {
  type    = number
  default = 50
}
variable "tags" {
  type    = map(string)
  default = {}
}
