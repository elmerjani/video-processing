locals {
  subnet_ids = var.subnet_ids == null ? var.public_subnet_ids : var.subnet_ids
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Allow HTTP traffic to the API load balancer"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_ingress_cidr_blocks) > 0 ? [1] : []

    content {
      description = "HTTP"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = var.allowed_ingress_cidr_blocks
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

resource "aws_lb" "api" {
  name               = "${var.name}-api"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = "/actuator/health"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
