ALTER TABLE video_jobs
    ADD COLUMN worker_id VARCHAR(255),
    ADD COLUMN claim_token VARCHAR(255),
    ADD COLUMN lease_expires_at TIMESTAMP(6) WITH TIME ZONE;