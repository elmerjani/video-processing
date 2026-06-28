# Video Processing Worker

A Go SQS consumer that safely turns uploaded videos into adaptive HLS streams and thumbnails with FFmpeg.

## Processing

For each job, the worker:

1. Long-polls SQS for one message.
2. Atomically claims the corresponding PostgreSQL row.
3. Renews both the database lease and SQS visibility while processing.
4. Downloads the source object from S3.
5. Uses `ffprobe` to inspect the input resolution.
6. Produces an appropriate H.264/AAC rendition ladder, six-second HLS segments, a master playlist, and a JPEG thumbnail.
7. Uploads the generated media to S3.
8. Completes the job with a claim-token-fenced database update, then deletes the SQS message.

## Duplicate delivery and failure handling

SQS provides at-least-once delivery, so duplicate messages are expected. Processing ownership is enforced by one conditional PostgreSQL update:

```text
QUEUED, or PROCESSING with an expired lease
                    ↓
PROCESSING + worker_id + unique claim_token + lease_expires_at
```

Only the worker holding the current claim token may renew, complete, or fail that job. A duplicate worker cannot overwrite the result of the active owner. Transient failures are retried through SQS; permanent failures and exhausted retries update the job and are removed or routed to the queue's DLQ.

## Output layout

```text
outputs/{jobId}/master.m3u8
outputs/{jobId}/{rendition}/index.m3u8
outputs/{jobId}/{rendition}/segment_00000.ts
thumbnails/{jobId}.jpg
```

## Configuration

| Variable | Description |
|---|---|
| `AWS_REGION` | AWS region |
| `VIDEO_JOBS_QUEUE_URL` | Source SQS queue URL |
| `VIDEO_BUCKET` | Source and output S3 bucket |
| `DATABASE_SECRET_ARN` | RDS credentials in Secrets Manager |
| `DATABASE_HOST` / `DATABASE_PORT` / `DATABASE_NAME` | Database connection metadata |
| `DATABASE_SSLMODE` | PostgreSQL SSL mode; defaults to `require` |
| `WORKER_ID` | Optional worker identity; defaults to host/process identity |
| `WORKER_VISIBILITY_TIMEOUT_SECONDS` | SQS visibility and database lease duration |
| `WORKER_MAX_RECEIVE_COUNT` | Attempts before marking a job failed |
| `WORKER_RECEIVE_WAIT_SECONDS` | SQS long-poll duration |

## Tests

```bash
go test ./...
go vet ./...
```

The tests cover message parsing, validation, atomic claims, ownership fencing, lease behavior, HLS key generation, rendition selection, playlists, and error classification.

## Container

The runtime image contains only the compiled worker, CA certificates, and FFmpeg, and runs as an unprivileged user.

```bash
docker build -t video-processing-worker .
```

