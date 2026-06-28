import json
import logging
import os
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_secret = None


def lambda_handler(event, _context):
    records = event.get("Records", [])
    if not records:
        logger.info("Ignoring event without S3 records")
        return {"processed": 0}

    import boto3
    import psycopg2

    s3 = boto3.client("s3")
    sqs = boto3.client("sqs")
    secret = database_secret(boto3.client("secretsmanager"))
    connection = psycopg2.connect(
        host=os.getenv("DATABASE_HOST") or secret.get("host"),
        port=os.getenv("DATABASE_PORT") or secret.get("port", "5432"),
        dbname=os.getenv("DATABASE_NAME") or secret.get("dbname"),
        user=secret.get("username"),
        password=secret.get("password"),
        sslmode=os.getenv("DATABASE_SSLMODE", "require"),
        connect_timeout=5,
    )

    processed = 0
    try:
        for record in records:
            upload = parse_s3_record(record)
            if upload is None:
                continue
            if handle_upload(connection, s3, sqs, upload):
                processed += 1
    finally:
        connection.close()

    return {"processed": processed}


def parse_s3_record(record):
    if record.get("eventSource") not in (None, "aws:s3"):
        return None

    s3_data = record.get("s3", {})
    bucket = s3_data.get("bucket", {}).get("name", "")
    key = unquote_plus(s3_data.get("object", {}).get("key", ""))
    expected_bucket = os.environ["VIDEO_BUCKET"]
    prefix = os.getenv("UPLOAD_PREFIX", "uploads/")

    if bucket != expected_bucket:
        logger.warning("Ignoring event for unexpected bucket=%s", bucket)
        return None
    if not key.startswith(prefix):
        logger.info("Ignoring object outside upload prefix key=%s", key)
        return None

    remainder = key[len(prefix):]
    parts = remainder.split("/", 1)
    if len(parts) != 2 or not parts[0] or not parts[1]:
        logger.warning("Ignoring malformed upload key=%s", key)
        return None

    return {"bucket": bucket, "key": key, "job_id": parts[0]}


def handle_upload(connection, s3, sqs, upload):
    head = s3.head_object(Bucket=upload["bucket"], Key=upload["key"])
    actual_size = head.get("ContentLength", 0)
    actual_content_type = head.get("ContentType", "")
    max_size = int(os.getenv("MAX_UPLOAD_FILE_BYTES", "524288000"))
    rejection_reason = None

    with connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                select status,
                       source_s3_key,
                       output_s3_key,
                       thumbnail_s3_key,
                       expected_content_type,
                       expected_size_bytes
                  from video_jobs
                 where id=%s::uuid
                 for update
                """,
                (upload["job_id"],),
            )
            row = cursor.fetchone()
            if row is None:
                raise ValueError(f"video job not found: {upload['job_id']}")

            (
                status,
                source_key,
                output_key,
                thumbnail_key,
                expected_content_type,
                expected_size_bytes,
            ) = row
            if source_key != upload["key"]:
                raise ValueError(
                    f"uploaded key does not match job source key: job={upload['job_id']}"
                )

            if actual_size <= 0:
                rejection_reason = "Uploaded object is empty"
            elif actual_size > max_size or actual_size != expected_size_bytes:
                rejection_reason = "Uploaded object size does not match signed request"
            elif actual_content_type != expected_content_type:
                rejection_reason = "Uploaded object content type does not match signed request"

            if rejection_reason is not None:
                cursor.execute(
                    """
                    update video_jobs
                       set status='FAILED', error_message=%s, updated_at=now()
                     where id=%s::uuid and status in ('PENDING_UPLOAD', 'QUEUED')
                    """,
                    (rejection_reason, upload["job_id"]),
                )
            elif status == "PENDING_UPLOAD":
                cursor.execute(
                    """
                    update video_jobs
                       set status='QUEUED', error_message=null, updated_at=now()
                     where id=%s::uuid and status='PENDING_UPLOAD'
                    """,
                    (upload["job_id"],),
                )
                status = "QUEUED"

            if rejection_reason is None and status != "QUEUED":
                logger.info(
                    "Ignoring duplicate upload event job_id=%s status=%s",
                    upload["job_id"],
                    status,
                )
                return False

    if rejection_reason is not None:
        s3.delete_object(Bucket=upload["bucket"], Key=upload["key"])
        logger.warning(
            "Rejected uploaded object job_id=%s reason=%s",
            upload["job_id"],
            rejection_reason,
        )
        return False

    message = build_job_message(upload, output_key, thumbnail_key)
    sqs.send_message(
        QueueUrl=os.environ["VIDEO_JOBS_QUEUE_URL"],
        MessageBody=json.dumps(message, separators=(",", ":")),
    )
    logger.info("Queued video job job_id=%s key=%s", upload["job_id"], upload["key"])
    return True


def build_job_message(upload, output_key=None, thumbnail_key=None):
    job_id = upload["job_id"]
    return {
        "jobId": job_id,
        "bucket": upload["bucket"],
        "sourceS3Key": upload["key"],
        "outputS3Key": output_key or f"outputs/{job_id}/master.m3u8",
        "thumbnailS3Key": thumbnail_key or f"thumbnails/{job_id}.jpg",
    }


def database_secret(secrets_client):
    global _secret
    if _secret is None:
        response = secrets_client.get_secret_value(
            SecretId=os.environ["DATABASE_SECRET_ARN"]
        )
        _secret = json.loads(response["SecretString"])
    return _secret
