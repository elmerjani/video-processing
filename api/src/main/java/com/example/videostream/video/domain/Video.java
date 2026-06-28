package com.example.videostream.video.domain;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "video_jobs")
public class Video {

    @Id
    private UUID id;

    @Column(nullable = false)
    private String originalFileName;

    @Column(nullable = false)
    private String sourceS3Key;

    @Column(nullable = false)
    private String ownerId;

    @Column(nullable = false, length = 100)
    private String expectedContentType;

    @Column(nullable = false)
    private Long expectedSizeBytes;

    private String outputS3Key;
    private String thumbnailS3Key;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private VideoStatus status;

    @Column(length = 2000)
    private String errorMessage;

    private String workerId;
    private String claimToken;
    private Instant leaseExpiresAt;

    @Column(nullable = false)
    private Instant createdAt;

    @Column(nullable = false)
    private Instant updatedAt;

    @PrePersist
    void onCreate() {
        if (id == null) id = UUID.randomUUID();
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
        if (status == null) status = VideoStatus.PENDING_UPLOAD;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public String getOriginalFileName() { return originalFileName; }
    public void setOriginalFileName(String originalFileName) { this.originalFileName = originalFileName; }

    public String getSourceS3Key() { return sourceS3Key; }
    public void setSourceS3Key(String sourceS3Key) { this.sourceS3Key = sourceS3Key; }

    public String getOwnerId() { return ownerId; }
    public void setOwnerId(String ownerId) { this.ownerId = ownerId; }

    public String getExpectedContentType() { return expectedContentType; }
    public void setExpectedContentType(String expectedContentType) { this.expectedContentType = expectedContentType; }

    public Long getExpectedSizeBytes() { return expectedSizeBytes; }
    public void setExpectedSizeBytes(Long expectedSizeBytes) { this.expectedSizeBytes = expectedSizeBytes; }

    public String getOutputS3Key() { return outputS3Key; }
    public void setOutputS3Key(String outputS3Key) { this.outputS3Key = outputS3Key; }

    public String getThumbnailS3Key() { return thumbnailS3Key; }
    public void setThumbnailS3Key(String thumbnailS3Key) { this.thumbnailS3Key = thumbnailS3Key; }

    public VideoStatus getStatus() { return status; }
    public void setStatus(VideoStatus status) { this.status = status; }

    public String getErrorMessage() { return errorMessage; }
    public void setErrorMessage(String errorMessage) { this.errorMessage = errorMessage; }

    public String getWorkerId() { return workerId; }
    public void setWorkerId(String workerId) { this.workerId = workerId; }

    public String getClaimToken() { return claimToken; }
    public void setClaimToken(String claimToken) { this.claimToken = claimToken; }

    public Instant getLeaseExpiresAt() { return leaseExpiresAt; }
    public void setLeaseExpiresAt(Instant leaseExpiresAt) { this.leaseExpiresAt = leaseExpiresAt; }

    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
