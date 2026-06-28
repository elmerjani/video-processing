data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "upload_handler" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.database_secret_arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["${var.bucket_arn}/${var.upload_prefix}*"]
  }

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [var.queue_arn]
  }
}

module "upload_handler" {
  source = "../lambda"

  name                         = "${var.name}-upload-handler"
  source_file                  = "${path.module}/lambda/handler.py"
  requirements_file            = "${path.module}/lambda/requirements.txt"
  application_policy_json      = data.aws_iam_policy_document.upload_handler.json
  vpc_id                       = var.vpc_id
  subnet_ids                   = var.subnet_ids
  timeout                      = 30
  memory_size                  = 256
  log_retention_in_days        = var.log_retention_in_days
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600

  environment_variables = {
    DATABASE_SECRET_ARN   = var.database_secret_arn
    DATABASE_HOST         = var.database_host
    DATABASE_PORT         = tostring(var.database_port)
    DATABASE_NAME         = var.database_name
    DATABASE_SSLMODE      = var.database_sslmode
    VIDEO_BUCKET          = var.bucket_name
    VIDEO_JOBS_QUEUE_URL  = var.queue_url
    UPLOAD_PREFIX         = var.upload_prefix
    MAX_UPLOAD_FILE_BYTES = "524288000"
  }

  tags = var.tags
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id   = "AllowExecutionFromS3"
  action         = "lambda:InvokeFunction"
  function_name  = module.upload_handler.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "upload_created" {
  bucket = var.bucket_name

  lambda_function {
    lambda_function_arn = module.upload_handler.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.upload_prefix
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
