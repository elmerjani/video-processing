resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = "Managed WAF rules for ${var.name}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimit"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "FORWARDED_IP"
        forwarded_ip_config {
          header_name       = "X-Forwarded-For"
          fallback_behavior = "MATCH"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = var.managed_rule_groups

    content {
      name     = rule.value
      priority = rule.key + 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.value}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = var.resource_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
