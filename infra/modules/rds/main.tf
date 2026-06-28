resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "Allow PostgreSQL from application subnets"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []

    content {
      description = "PostgreSQL from allowed CIDRs"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-rds-sg" })
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-db-subnet-group" })
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_period
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.name}-postgres-final-snapshot" : null

  tags = merge(var.tags, { Name = "${var.name}-postgres" })
}
