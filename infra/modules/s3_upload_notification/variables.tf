variable "bucket_name" { type = string }
variable "bucket_arn" { type = string }
variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "queue_url" { type = string }
variable "queue_arn" { type = string }
variable "database_secret_arn" { type = string }
variable "database_host" { type = string }
variable "database_port" {
  type    = number
  default = 5432
}
variable "database_name" { type = string }
variable "database_sslmode" {
  type    = string
  default = "require"
}
variable "log_retention_in_days" {
  type    = number
  default = 7
}
variable "upload_prefix" {
  type    = string
  default = "uploads/"
}
variable "tags" {
  type    = map(string)
  default = {}
}
