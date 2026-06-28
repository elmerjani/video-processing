variable "name" { type = string }
variable "max_image_count" {
  type    = number
  default = 5

  validation {
    condition     = var.max_image_count > 0
    error_message = "max_image_count must be greater than 0."
  }
}
variable "force_delete" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
