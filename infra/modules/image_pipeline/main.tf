data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "codepipeline_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${substr(var.project_name, 0, 25)}-artifacts-"
  force_destroy = var.artifact_bucket_force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.project_name}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
    ]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]
    resources = [aws_codebuild_project.this.arn]
  }

  statement {
    actions   = ["codestar-connections:UseConnection"]
    resources = [var.codestar_connection_arn]
  }

  statement {
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  statement {
    actions = ["iam:PassRole"]
    resources = [
      var.ecs_execution_role_arn,
      var.ecs_task_role_arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "ecs.amazonaws.com",
        "ecs-tasks.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "${var.project_name}-codepipeline"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_name}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.codebuild.arn,
      "${aws_cloudwatch_log_group.codebuild.arn}:*",
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${var.project_name}-codebuild"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

resource "aws_codebuild_project" "this" {
  name         = var.project_name
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = var.build_compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_URI"
      value = var.ecr_repository_url
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }

    environment_variable {
      name  = "COMPONENT_DIRECTORY"
      value = var.source_directory
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = var.buildspec_path
  }

  tags = var.tags
}

resource "aws_codepipeline" "this" {
  name           = var.project_name
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V2"
  execution_mode = "SUPERSEDED"

  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = [var.github_branch]
        }

        file_paths {
          includes = ["${var.source_directory}/**"]
        }
      }
    }
  }

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        BranchName           = var.github_branch
        ConnectionArn        = var.codestar_connection_arn
        DetectChanges        = "false"
        FullRepositoryId     = "${var.github_owner}/${var.github_repository}"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAndPushImage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = var.deploy_action_name
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = var.tags
}
