variable "name" { type = string }
variable "visibility_timeout_seconds" {
  type    = number
  default = 3600
}
variable "message_retention_seconds" {
  type    = number
  default = 345600
}
variable "receive_wait_time_seconds" {
  type    = number
  default = 20
}
variable "max_receive_count" {
  type    = number
  default = 3
}
variable "tags" {
  type    = map(string)
  default = {}
}
