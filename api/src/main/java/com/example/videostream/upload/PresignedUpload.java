package com.example.videostream.upload;

import java.time.Instant;
import java.util.Map;

public record PresignedUpload(
        String method,
        String url,
        Map<String, String> fields,
        Instant expiresAt
) {}
