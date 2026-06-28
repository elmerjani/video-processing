package com.example.videostream.video.web;

import com.example.videostream.quota.UploadQuotaExceededException;
import com.example.videostream.video.application.VideoNotFoundException;
import com.example.videostream.video.application.VideoService;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/videos")
public class VideoController {

    private final VideoService service;

    public VideoController(VideoService service) {
        this.service = service;
    }

    @PostMapping
    public CreateVideoResponse create(
            @AuthenticationPrincipal Jwt jwt,
            @Valid @RequestBody CreateVideoRequest request
    ) {
        return service.createVideo(jwt.getSubject(), request);
    }

    @GetMapping("/{id}")
    public VideoDetailsResponse get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return service.getVideo(jwt.getSubject(), id);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException exception) {
        return ResponseEntity.badRequest().body(Map.of("error", exception.getMessage()));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, String>> badRequestBody() {
        return ResponseEntity.badRequest().body(Map.of("error", "Request body is required"));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> validationError(MethodArgumentNotValidException exception) {
        String message = exception.getBindingResult().getFieldErrors().stream()
                .findFirst()
                .map(error -> error.getField() + " " + error.getDefaultMessage())
                .orElse("Invalid request");
        return ResponseEntity.badRequest().body(Map.of("error", message));
    }

    @ExceptionHandler(UploadQuotaExceededException.class)
    public ResponseEntity<Map<String, String>> quotaExceeded(UploadQuotaExceededException exception) {
        return ResponseEntity.status(429).body(Map.of("error", exception.getMessage()));
    }

    @ExceptionHandler(VideoNotFoundException.class)
    public ResponseEntity<Map<String, String>> notFound(VideoNotFoundException exception) {
        return ResponseEntity.status(404).body(Map.of("error", exception.getMessage()));
    }
}
