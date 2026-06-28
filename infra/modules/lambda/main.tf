data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

locals {
  build_dir      = "${path.root}/.terraform/build/${var.name}"
  source_dir     = "${local.build_dir}/python"
  zip_path       = "${local.build_dir}/${var.name}.zip"
  python_version = trimprefix(var.runtime, "python")
  wheel_platform = var.architecture == "arm64" ? "manylinux2014_aarch64" : "manylinux2014_x86_64"
}

resource "aws_sqs_queue" "failures" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600
  tags                      = var.tags
}

resource "aws_security_group" "this" {
  name        = var.name
  description = "Allow ${var.name} Lambda outbound access"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "execution" {
  source_policy_documents = var.application_policy_json == null ? [] : [var.application_policy_json]

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.failures.arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = var.name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "terraform_data" "build" {
  triggers_replace = [
    filesha256(var.source_file),
    filesha256(var.requirements_file),
  ]

  provisioner "local-exec" {
    command = "rm -rf '${local.source_dir}' && mkdir -p '${local.source_dir}' && python3 -m pip install --platform '${local.wheel_platform}' --implementation cp --python-version '${local.python_version}' --only-binary=:all: --upgrade -r '${var.requirements_file}' -t '${local.source_dir}' && cp '${var.source_file}' '${local.source_dir}/handler.py'"
  }
}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = local.source_dir
  output_path = local.zip_path

  depends_on = [terraform_data.build]
}

resource "aws_lambda_function" "this" {
  function_name    = var.name
  role             = aws_iam_role.this.arn
  handler          = var.handler
  runtime          = var.runtime
  architectures    = [var.architecture]
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size

  environment {
    variables = var.environment_variables
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.this.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.this,
    aws_iam_role_policy_attachment.vpc,
  ]

  tags = var.tags
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_event_age_in_seconds = var.maximum_event_age_in_seconds
  maximum_retry_attempts       = var.maximum_retry_attempts

  destination_config {
    on_failure {
      destination = aws_sqs_queue.failures.arn
    }
  }
}
