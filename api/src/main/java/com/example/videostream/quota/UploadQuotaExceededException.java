package com.example.videostream.quota;

public class UploadQuotaExceededException extends RuntimeException {
    public UploadQuotaExceededException(String message) {
        super(message);
    }
}
