variable "name" { type = string }
variable "enable_versioning" {
  type    = bool
  default = false
}
variable "force_destroy" {
  type    = bool
  default = false
}
variable "cors_allowed_origins" {
  type    = list(string)
  default = ["*"]
}
variable "tags" {
  type    = map(string)
  default = {}
}
