resource "aws_security_group" "vpc_link" {
  name        = "${var.name}-apigw-vpc-link"
  description = "Allow API Gateway VPC Link to reach the private ALB"
  vpc_id      = var.vpc_id

  egress {
    description     = "HTTP to ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  tags = merge(var.tags, { Name = "${var.name}-apigw-vpc-link-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_link" {
  security_group_id            = var.alb_security_group_id
  referenced_security_group_id = aws_security_group.vpc_link.id
  description                  = "HTTP from API Gateway VPC Link"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "${var.name}-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.jwt_issuer
    audience = [var.jwt_audience]
  }
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.name}-vpc-link"
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]
  tags               = var.tags
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = var.alb_listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = true
  tags        = var.tags

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }
}
