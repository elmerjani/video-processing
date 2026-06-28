variable "name" { type = string }
variable "video_bucket_arn" { type = string }
variable "jobs_queue_arn" { type = string }
variable "database_secret_arn" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
