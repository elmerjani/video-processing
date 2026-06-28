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

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class VideoServiceTest {

    @Mock
    private VideoRepository repo;

    @Mock
    private UploadUrlSigner uploadUrlSigner;

    @Mock
    private UploadQuotaService uploadQuotaService;

    private VideoService service;

    @BeforeEach
    void setUp() {
        service = new VideoService(repo, uploadUrlSigner, uploadQuotaService);
        ReflectionTestUtils.setField(service, "videosBucket", "test-videos");
        ReflectionTestUtils.setField(service, "maxFileBytes", 524288000L);
    }

    @Test
    void createVideoPersistsPendingUploadVideoAndReturnsUploadTarget() {
        Instant expiresAt = Instant.parse("2026-06-26T20:00:00Z");
        when(uploadUrlSigner.sign(anyString(), anyString(), anyString(), anyLong()))
                .thenAnswer(invocation -> new PresignedUpload(
                        "POST",
                        "https://upload.example/video",
                        Map.of("Content-Type", invocation.getArgument(2, String.class)),
                        expiresAt
                ));

        CreateVideoResponse response = service.createVideo("user-1", new CreateVideoRequest("clip #1.mp4", "video/mp4", 1024L));

        assertThat(response.videoId()).isNotNull();
        assertThat(response.status()).isEqualTo("PENDING_UPLOAD");
        assertThat(response.sourceS3Key())
                .isEqualTo("uploads/" + response.videoId() + "/clip__1.mp4");
        assertThat(response.upload().method()).isEqualTo("POST");
        assertThat(response.upload().url()).isEqualTo("https://upload.example/video");
        assertThat(response.upload().fields()).containsEntry("Content-Type", "video/mp4");
        assertThat(response.upload().expiresAt()).isEqualTo(expiresAt);

        ArgumentCaptor<Video> videoCaptor = ArgumentCaptor.forClass(Video.class);
        verify(repo).save(videoCaptor.capture());
        Video savedVideo = videoCaptor.getValue();
        assertThat(savedVideo.getId()).isEqualTo(response.videoId());
        assertThat(savedVideo.getOriginalFileName()).isEqualTo("clip #1.mp4");
        assertThat(savedVideo.getSourceS3Key()).isEqualTo(response.sourceS3Key());
        assertThat(savedVideo.getOwnerId()).isEqualTo("user-1");
        assertThat(savedVideo.getExpectedContentType()).isEqualTo("video/mp4");
        assertThat(savedVideo.getExpectedSizeBytes()).isEqualTo(1024L);
        assertThat(savedVideo.getStatus()).isEqualTo(VideoStatus.PENDING_UPLOAD);
        verify(uploadQuotaService).reserve("user-1", 1024L);
        verify(uploadUrlSigner).sign("test-videos", response.sourceS3Key(), "video/mp4", 1024L);
    }

    @Test
    void createVideoRejectsMissingBodyBeforeSideEffects() {
        assertThatThrownBy(() -> service.createVideo("user-1", null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Request body is required");

        verifyNoInteractions(repo, uploadUrlSigner, uploadQuotaService);
    }

    @Test
    void createVideoRejectsUnsupportedContentTypeBeforeQuotaReservation() {
        assertThatThrownBy(() -> service.createVideo(
                "user-1",
                new CreateVideoRequest("clip.exe", "application/octet-stream", 100L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Unsupported video content type");

        verifyNoInteractions(repo, uploadUrlSigner, uploadQuotaService);
    }

    @Test
    void createVideoUsesBasenameWhenClientSendsPath() {
        when(uploadUrlSigner.sign(anyString(), anyString(), anyString(), anyLong()))
                .thenAnswer(invocation -> new PresignedUpload(
                        "POST",
                        "https://upload.example/video",
                        Map.of("Content-Type", invocation.getArgument(2, String.class)),
                        Instant.now()
                ));

        CreateVideoResponse response = service.createVideo("user-1", new CreateVideoRequest("C:\\fakepath\\clip #1.mp4", "video/mp4", 100L));

        assertThat(response.sourceS3Key()).isEqualTo("uploads/" + response.videoId() + "/clip__1.mp4");
        verify(uploadUrlSigner).sign("test-videos", response.sourceS3Key(), "video/mp4", 100L);
    }

    @Test
    void getVideoReturnsRepositoryDetails() {
        UUID id = UUID.randomUUID();
        Video video = video(id, "clip.mp4", "uploads/video/clip.mp4", VideoStatus.PROCESSING);
        video.setOutputS3Key("outputs/video/master.m3u8");
        video.setThumbnailS3Key("thumbnails/video.jpg");
        video.setErrorMessage("still running");
        when(repo.findByIdAndOwnerId(id, "user-1")).thenReturn(Optional.of(video));

        VideoDetailsResponse response = service.getVideo("user-1", id);

        assertThat(response.videoId()).isEqualTo(id);
        assertThat(response.fileName()).isEqualTo("clip.mp4");
        assertThat(response.sourceS3Key()).isEqualTo("uploads/video/clip.mp4");
        assertThat(response.hlsS3Key()).isEqualTo("outputs/video/master.m3u8");
        assertThat(response.thumbnailS3Key()).isEqualTo("thumbnails/video.jpg");
        assertThat(response.status()).isEqualTo("PROCESSING");
        assertThat(response.errorMessage()).isEqualTo("still running");
    }

    private static Video video(UUID id, String originalFileName, String sourceS3Key, VideoStatus status) {
        Video video = new Video();
        video.setId(id);
        video.setOriginalFileName(originalFileName);
        video.setSourceS3Key(sourceS3Key);
        video.setOwnerId("user-1");
        video.setExpectedContentType("video/mp4");
        video.setExpectedSizeBytes(1024L);
        video.setStatus(status);
        return video;
    }
}
