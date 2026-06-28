variable "name" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "private_route_table_ids" { type = list(string) }
variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}
variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
}
variable "interface_services" {
  type = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "sqs",
    "cognito-idp",
  ]
}
variable "tags" {
  type    = map(string)
  default = {}
}
