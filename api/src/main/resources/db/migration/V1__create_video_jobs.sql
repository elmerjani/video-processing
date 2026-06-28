CREATE TABLE video_jobs (
                            id UUID PRIMARY KEY,
                            original_file_name VARCHAR(255) NOT NULL,
                            source_s3_key VARCHAR(255) NOT NULL,
                            output_s3_key VARCHAR(255),
                            thumbnail_s3_key VARCHAR(255),

                            status VARCHAR(255) NOT NULL,
                            error_message VARCHAR(2000),

                            created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
                            updated_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,

                            CONSTRAINT video_jobs_status_check
                                CHECK (
                                    status IN (
                                               'PENDING_UPLOAD',
                                               'QUEUED',
                                               'PROCESSING',
                                               'COMPLETED',
                                               'FAILED'
                                        )
                                    )
);
