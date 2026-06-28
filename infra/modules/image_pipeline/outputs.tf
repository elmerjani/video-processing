output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "pipeline_arn" {
  value = aws_codepipeline.this.arn
}

output "codebuild_project_name" {
  value = aws_codebuild_project.this.name
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "codestar_connection_arn" {
  value = var.codestar_connection_arn
}
