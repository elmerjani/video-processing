import os
import unittest
from unittest.mock import patch

import handler


class FakeCursor:
    def __init__(self, row):
        self.row = row
        self.updated = False

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query, _parameters):
        if "update video_jobs" in query:
            self.updated = True

    def fetchone(self):
        return self.row


class FakeConnection:
    def __init__(self, row):
        self.fake_cursor = FakeCursor(row)

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def cursor(self):
        return self.fake_cursor


class FakeS3:
    def __init__(self, size=1024, content_type="video/mp4"):
        self.size = size
        self.content_type = content_type
        self.deleted = []

    def head_object(self, **_kwargs):
        return {"ContentLength": self.size, "ContentType": self.content_type}

    def delete_object(self, **request):
        self.deleted.append(request)


class FakeSQS:
    def __init__(self):
        self.messages = []

    def send_message(self, **message):
        self.messages.append(message)


class HandlerTest(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(
            os.environ,
            {
                "VIDEO_BUCKET": "videos",
                "UPLOAD_PREFIX": "uploads/",
                "VIDEO_JOBS_QUEUE_URL": "https://sqs.example/jobs",
                "MAX_UPLOAD_FILE_BYTES": "524288000",
            },
            clear=False,
        )
        self.environment.start()

    def tearDown(self):
        self.environment.stop()

    def test_parse_s3_record(self):
        record = {
            "eventSource": "aws:s3",
            "s3": {
                "bucket": {"name": "videos"},
                "object": {"key": "uploads%2Fjob-1%2Fclip+one.mp4"},
            },
        }

        self.assertEqual(
            handler.parse_s3_record(record),
            {
                "bucket": "videos",
                "key": "uploads/job-1/clip one.mp4",
                "job_id": "job-1",
            },
        )

    def test_parse_s3_record_rejects_wrong_bucket_and_prefix(self):
        wrong_bucket = {
            "eventSource": "aws:s3",
            "s3": {
                "bucket": {"name": "other"},
                "object": {"key": "uploads/job-1/video.mp4"},
            },
        }
        output_key = {
            "eventSource": "aws:s3",
            "s3": {
                "bucket": {"name": "videos"},
                "object": {"key": "outputs/job-1/master.m3u8"},
            },
        }

        self.assertIsNone(handler.parse_s3_record(wrong_bucket))
        self.assertIsNone(handler.parse_s3_record(output_key))

    def test_build_job_message_uses_deterministic_output_keys(self):
        message = handler.build_job_message(
            {
                "bucket": "videos",
                "key": "uploads/job-1/video.mp4",
                "job_id": "job-1",
            }
        )

        self.assertEqual(message["outputS3Key"], "outputs/job-1/master.m3u8")
        self.assertEqual(message["thumbnailS3Key"], "thumbnails/job-1.jpg")

    def test_pending_upload_is_marked_queued_and_published(self):
        connection = FakeConnection(
            ("PENDING_UPLOAD", "uploads/job-1/video.mp4", None, None, "video/mp4", 1024)
        )
        sqs = FakeSQS()

        processed = handler.handle_upload(
            connection,
            FakeS3(),
            sqs,
            {
                "bucket": "videos",
                "key": "uploads/job-1/video.mp4",
                "job_id": "job-1",
            },
        )

        self.assertTrue(processed)
        self.assertTrue(connection.fake_cursor.updated)
        self.assertEqual(len(sqs.messages), 1)

    def test_queued_retry_publishes_again(self):
        connection = FakeConnection(("QUEUED", "uploads/job-1/video.mp4", None, None, "video/mp4", 1024))
        sqs = FakeSQS()

        processed = handler.handle_upload(
            connection,
            FakeS3(),
            sqs,
            {
                "bucket": "videos",
                "key": "uploads/job-1/video.mp4",
                "job_id": "job-1",
            },
        )

        self.assertTrue(processed)
        self.assertFalse(connection.fake_cursor.updated)
        self.assertEqual(len(sqs.messages), 1)

    def test_completed_duplicate_is_not_published(self):
        connection = FakeConnection(
            ("COMPLETED", "uploads/job-1/video.mp4", None, None, "video/mp4", 1024)
        )
        sqs = FakeSQS()

        processed = handler.handle_upload(
            connection,
            FakeS3(),
            sqs,
            {
                "bucket": "videos",
                "key": "uploads/job-1/video.mp4",
                "job_id": "job-1",
            },
        )

        self.assertFalse(processed)
        self.assertEqual(sqs.messages, [])

    def test_mismatched_size_is_failed_deleted_and_not_published(self):
        connection = FakeConnection(
            ("PENDING_UPLOAD", "uploads/job-1/video.mp4", None, None, "video/mp4", 1024)
        )
        s3 = FakeS3(size=2048)
        sqs = FakeSQS()

        processed = handler.handle_upload(
            connection,
            s3,
            sqs,
            {
                "bucket": "videos",
                "key": "uploads/job-1/video.mp4",
                "job_id": "job-1",
            },
        )

        self.assertFalse(processed)
        self.assertEqual(len(s3.deleted), 1)
        self.assertEqual(sqs.messages, [])


if __name__ == "__main__":
    unittest.main()
