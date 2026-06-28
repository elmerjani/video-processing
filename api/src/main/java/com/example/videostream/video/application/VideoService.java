package com.example.videostream.video.application;

import com.example.videostream.quota.UploadQuotaService;
import com.example.videostream.upload.PresignedUpload;
import com.example.videostream.upload.UploadUrlSigner;
import com.example.videostream.video.domain.Video;
import com.example.videostream.video.domain.VideoStatus;
import com.example.videostream.video.persistence.VideoRepository;
import com.example.videostream.video.web.CreateVideoRequest;
import com.example.videostream.video.web.CreateVideoResponse;
import com.example.videostream.video.web.VideoDetailsResponse;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;
import java.util.Set;

@Service
public class VideoService {

    private final VideoRepository repo;
    private final UploadUrlSigner uploadUrlSigner;
    private final UploadQuotaService uploadQuotaService;

    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of(
            "video/mp4",
            "video/quicktime",
            "video/webm"
    );

    @Value("${app.aws.videos-bucket}")
    private String videosBucket;

    @Value("${app.upload.max-file-bytes:524288000}")
    private long maxFileBytes;

    public VideoService(VideoRepository repo, UploadUrlSigner uploadUrlSigner, UploadQuotaService uploadQuotaService) {
        this.repo = repo;
        this.uploadUrlSigner = uploadUrlSigner;
        this.uploadQuotaService = uploadQuotaService;
    }

    @Transactional
    public CreateVideoResponse createVideo(String ownerId, CreateVideoRequest request) {
        if (request == null) {
            throw new IllegalArgumentException("Request body is required");
        }

        if (ownerId == null || ownerId.isBlank()) {
            throw new IllegalArgumentException("Authenticated user is required");
        }

        UUID videoId = UUID.randomUUID();
        String originalName = normalizeFileName(request.fileName());
        String sanitizedName = sanitizeFileName(originalName);
        String contentType = validateContentType(request.contentType());
        long sizeBytes = validateSize(request.sizeBytes());
        String sourceKey = "uploads/" + videoId + "/" + sanitizedName;

        uploadQuotaService.reserve(ownerId, sizeBytes);

        Video video = new Video();
        video.setId(videoId);
        video.setOriginalFileName(originalName);
        video.setSourceS3Key(sourceKey);
        video.setOwnerId(ownerId);
        video.setExpectedContentType(contentType);
        video.setExpectedSizeBytes(sizeBytes);
        video.setStatus(VideoStatus.PENDING_UPLOAD);

        repo.save(video);

        PresignedUpload upload = uploadUrlSigner.sign(videosBucket, sourceKey, contentType, sizeBytes);
        return new CreateVideoResponse(
                videoId,
                video.getStatus().name(),
                video.getSourceS3Key(),
                new CreateVideoResponse.Upload(
                        upload.method(),
                        upload.url(),
                        upload.fields(),
                        upload.expiresAt()
                )
        );
    }

    public VideoDetailsResponse getVideo(String ownerId, UUID id) {
        Video video = repo.findByIdAndOwnerId(id, ownerId).orElseThrow(VideoNotFoundException::new);
        return new VideoDetailsResponse(
                video.getId(),
                video.getOriginalFileName(),
                video.getSourceS3Key(),
                video.getOutputS3Key(),
                video.getThumbnailS3Key(),
                video.getStatus().name(),
                video.getErrorMessage(),
                video.getCreatedAt(),
                video.getUpdatedAt()
        );
    }

    private static String normalizeFileName(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return "video.bin";
        }
        String normalized = fileName.replace('\\', '/');
        int lastSlash = normalized.lastIndexOf('/');
        if (lastSlash >= 0) {
            normalized = normalized.substring(lastSlash + 1);
        }
        return normalized.isBlank() ? "video.bin" : normalized;
    }

    private static String sanitizeFileName(String fileName) {
        String sanitized = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");
        return sanitized.isBlank() ? "video.bin" : sanitized;
    }

    private static String validateContentType(String contentType) {
        if (!ALLOWED_CONTENT_TYPES.contains(contentType)) {
            throw new IllegalArgumentException("Unsupported video content type");
        }
        return contentType;
    }

    private long validateSize(Long sizeBytes) {
        if (sizeBytes == null || sizeBytes < 1 || sizeBytes > maxFileBytes) {
            throw new IllegalArgumentException("Video exceeds the allowed upload size");
        }
        return sizeBytes;
    }
}
