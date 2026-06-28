variable "name" { type = string }
variable "resource_arn" { type = string }
variable "rate_limit" {
  type    = number
  default = 1000
}
variable "managed_rule_groups" {
  type = list(string)
  default = [
    "AWSManagedRulesAmazonIpReputationList",
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
    "AWSManagedRulesSQLiRuleSet",
  ]
}
variable "tags" {
  type    = map(string)
  default = {}
}
