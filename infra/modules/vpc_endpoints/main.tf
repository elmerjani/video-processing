resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "Allow private subnet HTTPS access to VPC endpoints"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []

    content {
      description = "HTTPS from allowed CIDRs"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = toset(var.allowed_security_group_ids)

    content {
      description     = "HTTPS from application security group"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpc-endpoints-sg" })
}

data "aws_subnet" "private" {
  count = length(var.private_subnet_ids)

  id = var.private_subnet_ids[count.index]
}

data "aws_vpc_endpoint_service" "interface" {
  for_each = toset(var.interface_services)

  service      = each.value
  service_type = "Interface"
}

locals {
  # PrivateLink services are not necessarily available in every AZ. For
  # example, Cognito can support us-east-1a/1c/1d while a VPC also has a
  # subnet in us-east-1b. Supplying that subnet makes CreateVpcEndpoint fail.
  interface_service_subnet_ids = {
    for service in var.interface_services : service => [
      for index, subnet_id in var.private_subnet_ids : subnet_id
      if contains(
        data.aws_vpc_endpoint_service.interface[service].availability_zones,
        data.aws_subnet.private[index].availability_zone
      )
    ]
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_service_subnet_ids[each.value]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  lifecycle {
    precondition {
      condition     = length(local.interface_service_subnet_ids[each.value]) > 0
      error_message = "The ${each.value} VPC endpoint service is not available in any configured private subnet Availability Zone."
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.value}-endpoint" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-s3-endpoint" })
}
