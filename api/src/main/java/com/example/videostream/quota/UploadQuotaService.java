package com.example.videostream.quota;

import com.example.videostream.video.domain.VideoStatus;
import com.example.videostream.video.persistence.VideoRepository;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class UploadQuotaService {

    private static final List<VideoStatus> ACTIVE_STATUSES = List.of(
            VideoStatus.PENDING_UPLOAD,
            VideoStatus.QUEUED,
            VideoStatus.PROCESSING
    );

    private final NamedParameterJdbcTemplate jdbc;
    private final VideoRepository videoRepository;

    @Value("${app.upload.max-active-jobs:3}")
    private int maxActiveJobs;

    @Value("${app.upload.max-daily-jobs:20}")
    private int maxDailyJobs;

    @Value("${app.upload.max-daily-bytes:5368709120}")
    private long maxDailyBytes;

    public UploadQuotaService(NamedParameterJdbcTemplate jdbc, VideoRepository videoRepository) {
        this.jdbc = jdbc;
        this.videoRepository = videoRepository;
    }

    public void reserve(String ownerId, long sizeBytes) {
        MapSqlParameterSource parameters = new MapSqlParameterSource()
                .addValue("ownerId", ownerId)
                .addValue("sizeBytes", sizeBytes)
                .addValue("maxDailyJobs", maxDailyJobs)
                .addValue("maxDailyBytes", maxDailyBytes);

        Integer reserved = jdbc.query("""
                insert into user_daily_upload_usage (
                    owner_id, usage_date, upload_count, reserved_bytes
                )
                select :ownerId, current_date, 1, :sizeBytes
                 where :maxDailyJobs >= 1
                   and :sizeBytes <= :maxDailyBytes
                on conflict (owner_id, usage_date)
                do update set
                    upload_count = user_daily_upload_usage.upload_count + 1,
                    reserved_bytes = user_daily_upload_usage.reserved_bytes + :sizeBytes
                where user_daily_upload_usage.upload_count < :maxDailyJobs
                  and user_daily_upload_usage.reserved_bytes + :sizeBytes <= :maxDailyBytes
                returning upload_count
                """, parameters, resultSet -> resultSet.next() ? resultSet.getInt(1) : null);

        if (reserved == null) {
            throw new UploadQuotaExceededException("Daily upload quota exceeded");
        }

        long activeJobs = videoRepository.countByOwnerIdAndStatusIn(ownerId, ACTIVE_STATUSES);
        if (activeJobs >= maxActiveJobs) {
            throw new UploadQuotaExceededException("Too many active video jobs");
        }
    }
}
