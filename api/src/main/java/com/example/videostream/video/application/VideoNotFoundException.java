package com.example.videostream.video.application;

public class VideoNotFoundException extends RuntimeException {
    public VideoNotFoundException() {
        super("Video not found");
    }
}
