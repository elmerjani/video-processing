package com.example.videostream.video.web;

import java.time.Instant;
import java.util.UUID;

public record VideoDetailsResponse(
        UUID videoId,
        String fileName,
        String sourceS3Key,
        String hlsS3Key,
        String thumbnailS3Key,
        String status,
        String errorMessage,
        Instant createdAt,
        Instant updatedAt
) {}
