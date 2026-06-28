package com.example.videostream.video.web;

import com.example.videostream.quota.UploadQuotaService;
import com.example.videostream.upload.PresignedUpload;
import com.example.videostream.upload.UploadUrlSigner;
import com.example.videostream.video.domain.Video;
import com.example.videostream.video.domain.VideoStatus;
import com.example.videostream.video.persistence.VideoRepository;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.springframework.security.oauth2.jwt.JwtDecoder;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK, properties = {
        "spring.datasource.url=jdbc:h2:mem:videocontroller;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.flyway.enabled=false",
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "app.aws.videos-bucket=test-videos",
        "spring.security.oauth2.resourceserver.jwt.issuer-uri=https://issuer.example",
        "app.aws.cognito-client-id=test-client"
})
class VideoControllerIntegrationTest {

    @Autowired
    private WebApplicationContext webApplicationContext;

    @Autowired
    private VideoRepository repository;

    @MockitoBean
    private UploadUrlSigner uploadUrlSigner;

    @MockitoBean
    private UploadQuotaService uploadQuotaService;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext)
                .apply(springSecurity())
                .build();
        repository.deleteAll();
        reset(uploadUrlSigner);
    }

    @Test
    void createVideoAcceptsJsonPersistsVideoAndReturnsUploadTarget() throws Exception {
        Instant expiresAt = Instant.parse("2026-06-26T20:00:00Z");
        when(uploadUrlSigner.sign(any(), any(), any(), anyLong()))
                .thenReturn(new PresignedUpload("POST", "https://upload.example/video", Map.of("Content-Type", "video/mp4"), expiresAt));

        MvcResult result = mockMvc.perform(post("/videos")
                        .with(jwt().jwt(token -> token.subject("user-1").claim("token_use", "access")))
                        .contentType("application/json")
                        .content("""
                                {
                                  "fileName": "clip #1.mp4",
                                  "contentType": "video/mp4",
                                  "sizeBytes": 1024
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.videoId").isNotEmpty())
                .andExpect(jsonPath("$.status").value("PENDING_UPLOAD"))
                .andExpect(jsonPath("$.sourceS3Key").isNotEmpty())
                .andExpect(jsonPath("$.upload.method").value("POST"))
                .andExpect(jsonPath("$.upload.url").value("https://upload.example/video"))
                .andExpect(jsonPath("$.upload.fields.Content-Type").value("video/mp4"))
                .andReturn();

        UUID videoId = UUID.fromString(objectMapper.readTree(result.getResponse().getContentAsString()).get("videoId").asText());

        Video savedVideo = repository.findById(videoId).orElseThrow();
        assertThat(savedVideo.getOriginalFileName()).isEqualTo("clip #1.mp4");
        assertThat(savedVideo.getSourceS3Key()).isEqualTo("uploads/" + videoId + "/clip__1.mp4");
        assertThat(savedVideo.getOwnerId()).isEqualTo("user-1");
        assertThat(savedVideo.getExpectedSizeBytes()).isEqualTo(1024L);
        assertThat(savedVideo.getStatus()).isEqualTo(VideoStatus.PENDING_UPLOAD);
        assertThat(savedVideo.getCreatedAt()).isNotNull();
        assertThat(savedVideo.getUpdatedAt()).isNotNull();
    }

    @Test
    void createVideoRejectsMissingJsonBody() throws Exception {
        mockMvc.perform(post("/videos")
                        .with(jwt().jwt(token -> token.subject("user-1")))
                        .contentType("application/json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").isNotEmpty());

        assertThat(repository.count()).isZero();
    }

    @Test
    void getVideoReturnsPersistedVideoDetails() throws Exception {
        UUID id = UUID.randomUUID();
        Video video = new Video();
        video.setId(id);
        video.setOriginalFileName("clip.mp4");
        video.setSourceS3Key("uploads/" + id + "/clip.mp4");
        video.setOwnerId("user-1");
        video.setExpectedContentType("video/mp4");
        video.setExpectedSizeBytes(1024L);
        video.setOutputS3Key("outputs/" + id + "/master.m3u8");
        video.setThumbnailS3Key("thumbnails/" + id + ".jpg");
        video.setStatus(VideoStatus.COMPLETED);
        repository.saveAndFlush(video);

        mockMvc.perform(get("/videos/{id}", id)
                        .with(jwt().jwt(token -> token.subject("user-1"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.videoId").value(id.toString()))
                .andExpect(jsonPath("$.fileName").value("clip.mp4"))
                .andExpect(jsonPath("$.sourceS3Key").value("uploads/" + id + "/clip.mp4"))
                .andExpect(jsonPath("$.hlsS3Key").value("outputs/" + id + "/master.m3u8"))
                .andExpect(jsonPath("$.thumbnailS3Key").value("thumbnails/" + id + ".jpg"))
                .andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.createdAt").isNotEmpty())
                .andExpect(jsonPath("$.updatedAt").isNotEmpty());
    }

    @Test
    void getVideoReturnsBadRequestForMissingVideo() throws Exception {
        UUID id = UUID.randomUUID();

        mockMvc.perform(get("/videos/{id}", id)
                        .with(jwt().jwt(token -> token.subject("user-1"))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("Video not found"));
    }

    @Test
    void videosRequireAuthentication() throws Exception {
        mockMvc.perform(post("/videos")
                        .contentType("application/json")
                        .content("""
                                {"fileName":"clip.mp4","contentType":"video/mp4","sizeBytes":1024}
                                """))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void userCannotReadAnotherUsersVideo() throws Exception {
        UUID id = UUID.randomUUID();
        Video video = new Video();
        video.setId(id);
        video.setOwnerId("user-1");
        video.setOriginalFileName("clip.mp4");
        video.setSourceS3Key("uploads/" + id + "/clip.mp4");
        video.setExpectedContentType("video/mp4");
        video.setExpectedSizeBytes(1024L);
        video.setStatus(VideoStatus.PENDING_UPLOAD);
        repository.saveAndFlush(video);

        mockMvc.perform(get("/videos/{id}", id)
                        .with(jwt().jwt(token -> token.subject("user-2"))))
                .andExpect(status().isNotFound());
    }
}
