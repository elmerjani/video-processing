package com.example.videostream.video.web;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

public record CreateVideoResponse(
        UUID videoId,
        String status,
        String sourceS3Key,
        Upload upload
) {
    public record Upload(
            String method,
            String url,
            Map<String, String> fields,
            Instant expiresAt
    ) {}
}
