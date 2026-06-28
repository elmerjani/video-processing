variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" {
  type    = list(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
