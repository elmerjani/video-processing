resource "aws_s3_bucket" "videos" {
  bucket_prefix = "${var.name}-videos-"
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = "${var.name}-videos" })
}

resource "aws_s3_bucket_public_access_block" "videos" {
  bucket = aws_s3_bucket.videos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "videos" {
  bucket = aws_s3_bucket.videos.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_cors_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["POST", "PUT", "GET", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
