variable "name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "subnet_ids" {
  type     = list(string)
  default  = null
  nullable = true
}
variable "internal" {
  type    = bool
  default = false
}
variable "allowed_ingress_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "container_port" { type = number }
variable "tags" {
  type    = map(string)
  default = {}
}
