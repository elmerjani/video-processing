variable "name" { type = string }
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
