ALTER TABLE video_jobs
    ADD COLUMN owner_id VARCHAR(255),
    ADD COLUMN expected_content_type VARCHAR(100),
    ADD COLUMN expected_size_bytes BIGINT;

UPDATE video_jobs
SET owner_id = COALESCE(owner_id, 'legacy'),
    expected_content_type = COALESCE(expected_content_type, 'application/octet-stream'),
    expected_size_bytes = COALESCE(expected_size_bytes, 0)
WHERE owner_id IS NULL
   OR expected_content_type IS NULL
   OR expected_size_bytes IS NULL;

ALTER TABLE video_jobs
    ALTER COLUMN owner_id SET NOT NULL,
    ALTER COLUMN expected_content_type SET NOT NULL,
    ALTER COLUMN expected_size_bytes SET NOT NULL;

CREATE INDEX idx_video_jobs_owner_id ON video_jobs(owner_id);
CREATE INDEX idx_video_jobs_owner_status ON video_jobs(owner_id, status);

CREATE TABLE user_daily_upload_usage (
    owner_id VARCHAR(255) NOT NULL,
    usage_date DATE NOT NULL,
    upload_count INTEGER NOT NULL DEFAULT 0,
    reserved_bytes BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (owner_id, usage_date),
    CONSTRAINT user_daily_upload_usage_nonnegative
        CHECK (upload_count >= 0 AND reserved_bytes >= 0)
);
