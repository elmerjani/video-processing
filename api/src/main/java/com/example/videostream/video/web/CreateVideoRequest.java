package com.example.videostream.video.web;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record CreateVideoRequest(
        @NotBlank @Size(max = 255) String fileName,
        @NotBlank @Size(max = 100) String contentType,
        @NotNull @Min(1) @Max(524288000) Long sizeBytes
) {}
