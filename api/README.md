# Video API

The Spring Boot API authenticates users, owns the video-job lifecycle, enforces upload quotas, and issues constrained policies for direct S3 uploads.

## Responsibilities

- Validate Cognito access tokens at both API Gateway and Spring Security
- Scope every video lookup to the authenticated Cognito subject
- Enforce allowed media types, maximum file size, active-job limits, and daily quotas
- Persist video jobs in PostgreSQL
- Generate AWS Signature V4 S3 POST policies with an exact key, content type, size, and expiration
- Expose upload and processing status without transferring video bytes through the API
- Apply versioned PostgreSQL migrations with Flyway before Hibernate validation

## Package structure

```text
com.example.videostream
├── VideoStreamApplication
├── config
│   ├── AwsConfig
│   └── DatabaseSecretEnvironmentPostProcessor
├── security
│   └── SecurityConfig
├── upload
│   ├── UploadUrlSigner
│   ├── S3UploadUrlSigner
│   └── PresignedUpload
├── quota
│   ├── UploadQuotaService
│   └── UploadQuotaExceededException
└── video
    ├── domain
    │   ├── Video
    │   └── VideoStatus
    ├── persistence
    │   └── VideoRepository
    ├── application
    │   ├── VideoService
    │   └── VideoNotFoundException
    └── web
        ├── VideoController
        ├── CreateVideoRequest
        ├── CreateVideoResponse
        └── VideoDetailsResponse
```

The package boundaries keep HTTP contracts, orchestration, persistence, security, quotas, and AWS-specific upload signing independent and easy to test.

## API

All `/videos` endpoints require an access token:

```http
Authorization: Bearer <cognito-access-token>
```

### Create an upload

```http
POST /videos
Content-Type: application/json

{
  "fileName": "demo.mp4",
  "contentType": "video/mp4",
  "sizeBytes": 10485760
}
```

The response contains a video ID plus an S3 URL and signed multipart form fields:

```json
{
  "videoId": "7fcafcc4-3597-4a47-a93f-c91557ae81bf",
  "status": "PENDING_UPLOAD",
  "sourceS3Key": "uploads/7fcafcc4-3597-4a47-a93f-c91557ae81bf/demo.mp4",
  "upload": {
    "method": "POST",
    "url": "https://example-bucket.s3.us-east-1.amazonaws.com/",
    "fields": {
      "key": "uploads/7fcafcc4-3597-4a47-a93f-c91557ae81bf/demo.mp4",
      "Content-Type": "video/mp4",
      "policy": "...",
      "x-amz-signature": "..."
    },
    "expiresAt": "2026-06-28T12:15:00Z"
  }
}
```

The client must send every returned field and the file in one `multipart/form-data` POST. It must not convert this request into an S3 PUT.

### Read status

```http
GET /videos/{videoId}
```

The response includes the job state, error information, and HLS/thumbnail S3 keys when processing completes. Looking up another user's video returns `404`.

## Job states

```text
PENDING_UPLOAD -> QUEUED -> PROCESSING -> COMPLETED
                                      \-> FAILED
```

## Configuration

| Variable | Description |
|---|---|
| `COGNITO_ISSUER_URI` | Cognito user-pool issuer URL |
| `COGNITO_CLIENT_ID` | Expected Cognito app-client ID |
| `VIDEO_BUCKET` | S3 bucket used for uploads and processed media |
| `AWS_REGION` | AWS region |
| `DATABASE_SECRET_ARN` | Secrets Manager ARN used in AWS |
| `DATABASE_URL` | Direct JDBC URL used for local development |
| `DATABASE_USERNAME` / `DATABASE_PASSWORD` | Local database credentials |
| `DATABASE_SCHEMA` | Flyway and Hibernate schema; defaults to `public` |
| `MAX_UPLOAD_FILE_BYTES` | Maximum accepted upload size |
| `MAX_ACTIVE_VIDEO_JOBS` | Maximum active jobs per user |
| `MAX_DAILY_VIDEO_JOBS` | Maximum daily jobs per user |
| `MAX_DAILY_UPLOAD_BYTES` | Maximum daily reserved bytes per user |

## Local development

Start PostgreSQL, export the database and Cognito variables, then run:

```bash
./mvnw spring-boot:run
```

Flyway applies migrations from `src/main/resources/db/migration` before Hibernate validates the schema.

## Tests

```bash
./mvnw test
```

The suite covers API authentication and ownership, validation, repository behavior, quota enforcement, and signed POST-policy constraints.

## Container

```bash
docker build -t video-processing-api .
docker run --rm -p 8080:8080 --env-file .env video-processing-api
```

Do not commit the `.env` file.
