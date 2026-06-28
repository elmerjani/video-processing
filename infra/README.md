# AWS Infrastructure

Terraform provisions the complete private AWS backend as reusable modules with independent dev and production roots.

```text
infra/
  modules/
    vpc/
    ecs/
    alb/
    ecr/
    rds/
    s3/
    vpc_endpoints/
    api_gateway/
    waf/
    sqs/
    iam/
    cloudwatch/
    cognito/
    image_pipeline/
    lambda/
    s3_upload_notification/
  envs/
    dev/
    prod/
```

## Provisioned architecture

- Cognito user pool and JWT app client
- API Gateway HTTP API, JWT authorizer, throttling, and VPC Link
- AWS WAF, an internal Application Load Balancer, and private ECS Fargate services
- S3 direct uploads and private HLS/thumbnail storage
- S3-triggered validation Lambda and failure DLQ
- SQS processing queue and worker DLQ
- Encrypted PostgreSQL RDS with a Secrets Manager-managed password
- VPC endpoints for private AWS service access
- ECR repositories and optional CodePipeline/CodeBuild image pipelines
- CloudWatch logs, metrics, worker autoscaling, alarms, and SNS notifications

## Quick start

Run Terraform from an environment directory:

```bash
cd infra/envs/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

`terraform plan` is safe to run, but `terraform apply` creates billable AWS resources.

The dev environment prioritizes inexpensive teardown. The prod environment defaults to regular Fargate, two API tasks, Multi-AZ RDS, 14-day backups, deletion protection, storage autoscaling, S3 versioning, Container Insights, enabled alarms, and non-destructive storage settings.

## Container images

The API service defaults to the ECR repository created by Terraform:

```text
<api_ecr_repository_url>:<image_tag>
```

For a first deployment, create the ECR repositories before starting ECS, then build and push the API image:

```bash
cd infra/envs/dev
terraform apply -target=module.ecr
REPO_URL="$(terraform output -raw api_ecr_repository_url)"
REGION="$(echo "$REPO_URL" | cut -d. -f4)"
REGISTRY="$(echo "$REPO_URL" | cut -d/ -f1)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build -t "${REPO_URL}:latest" ../../../api
docker push "${REPO_URL}:latest"
terraform apply
```

Build the worker from `../../../worker` and push it to `worker_ecr_repository_url` in the same way. Set `image_tag` in `terraform.tfvars` if you use a tag other than `latest`; the full `api_image` and `worker_image` values can also be overridden.

## GitHub image pipeline

If local Docker is unavailable, enable the API image pipeline instead:

```hcl
enable_api_pipeline            = true
api_pipeline_github_owner      = "your-github-user-or-org"
api_pipeline_github_repository = "your-github-repo"
api_pipeline_github_branch     = "main"
```

The pipeline uses GitHub through AWS CodeStar Connections, builds the Docker image in CodeBuild, pushes both the commit tag and `latest` to ECR, and deploys the new image to the ECS API service.

If `api_pipeline_codestar_connection_arn` is unset, Terraform creates the GitHub connection. After `terraform apply`, authorize the pending connection in the AWS console under Developer Tools > Connections. The first successful pipeline run will create the image in ECR, so local Docker is not required.

This pipeline does not use CodeArtifact. In the monorepo, CodeBuild uses `api/buildspec.yml` or `worker/buildspec.yml`, builds the corresponding component directory, and emits `imagedefinitions.json` for the ECS deploy action.

## Database secret

RDS manages the database master password in AWS Secrets Manager. ECS receives the secret ARN and non-secret connection metadata as environment variables, and the application fetches the secret at startup through the ECS task role.

The API task role can read only that database secret and can create signed uploads under the S3 `uploads/` prefix. S3 object-created events invoke the validation Lambda; only validated objects are moved to `QUEUED` and published to the jobs SQS queue.

## Private production topology

The environment defaults run ECS tasks in private subnets behind an internal ALB. API Gateway reaches the ALB through a VPC Link, and AWS WAF is associated with the ALB. VPC endpoints are created for ECR, CloudWatch Logs, Secrets Manager, SQS, and S3 so ECS can pull images and call AWS services without a NAT Gateway.

Use this output as the public API base URL:

```bash
terraform output -raw api_gateway_invoke_url
```

The ALB DNS output is internal when `alb_internal = true`.

## Monitoring and alerts

Production creates CloudWatch alarms for API 5xx responses, worker backlog, worker DLQ messages, upload-handler DLQ messages, high RDS CPU, and low RDS storage. All alarms publish state changes to the production SNS alerts topic.

To receive email notifications, set:

```hcl
alarm_notification_email = "oncall@example.com"
```

AWS sends a confirmation email after apply; notifications are not delivered until the subscription is confirmed.

## Production safeguards

- ECS deployment circuit breakers automatically roll back failed API and worker deployments.
- RDS is private, encrypted, Multi-AZ, backed up for 14 days, deletion-protected, and configured for a final snapshot.
- S3 versioning is enabled and force-destroy is disabled.
- ECR and pipeline artifact buckets cannot be force-deleted while non-empty.
- CloudWatch log retention is 30 days.

## Teardown behavior

The dev environment keeps force-destroy behavior for convenient teardown. Production defaults disable force-destroy for the video bucket, pipeline artifact buckets, and ECR repositories, and enable RDS deletion protection with a final snapshot.

## Cost notes

The private production topology is more expensive than the earlier low-cost layout because API Gateway, WAF, and multiple interface VPC endpoints are billable resources. To return to the cheapest topology, override:

```hcl
ecs_assign_public_ip  = true
alb_internal          = false
create_vpc_endpoints  = false
enable_api_gateway    = false
enable_waf            = false
```

Production defaults prioritize resilience: regular Fargate, two API tasks, larger FFmpeg workers, Multi-AZ RDS with 14-day backups and storage autoscaling, deletion protection, Container Insights, metric alarms, 30-day logs, S3 versioning, and non-destructive storage settings. Set `alarm_notification_email` and confirm the SNS subscription to receive alarm notifications.
