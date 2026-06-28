variable "name" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}
variable "database_name" { type = string }
variable "database_username" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "max_allocated_storage" {
  type    = number
  default = null
}
variable "backup_retention_period" {
  type    = number
  default = 0
}
variable "deletion_protection" { type = bool }
variable "multi_az" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
