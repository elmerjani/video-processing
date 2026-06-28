package com.example.videostream.upload;

public interface UploadUrlSigner {
    PresignedUpload sign(String bucket, String key, String contentType, long sizeBytes);
}
