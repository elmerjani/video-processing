package com.example.videostream.video.persistence;

import com.example.videostream.video.domain.Video;
import com.example.videostream.video.domain.VideoStatus;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:videorepository;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.flyway.enabled=false",
        "spring.jpa.hibernate.ddl-auto=create-drop"
})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class VideoRepositoryTest {

    @Autowired
    private VideoRepository repository;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void persistsDefaultStatusAndTimestampsOnCreate() {
        Video video = new Video();
        video.setOriginalFileName("clip.mp4");
        video.setSourceS3Key("uploads/video/clip.mp4");
        video.setOwnerId("user-1");
        video.setExpectedContentType("video/mp4");
        video.setExpectedSizeBytes(1024L);

        Video saved = repository.saveAndFlush(video);
        entityManager.clear();

        Video found = repository.findById(saved.getId()).orElseThrow();
        assertThat(found.getStatus()).isEqualTo(VideoStatus.PENDING_UPLOAD);
        assertThat(found.getCreatedAt()).isNotNull();
        assertThat(found.getUpdatedAt()).isNotNull();
        assertThat(found.getUpdatedAt()).isEqualTo(found.getCreatedAt());
    }

    @Test
    void updatesStatusOutputFieldsAndUpdatedTimestamp() {
        Video video = new Video();
        video.setOriginalFileName("clip.mp4");
        video.setSourceS3Key("uploads/video/clip.mp4");
        video.setOwnerId("user-1");
        video.setExpectedContentType("video/mp4");
        video.setExpectedSizeBytes(1024L);
        video.setStatus(VideoStatus.PROCESSING);

        Video saved = repository.saveAndFlush(video);
        entityManager.clear();

        Video found = repository.findById(saved.getId()).orElseThrow();
        found.setStatus(VideoStatus.COMPLETED);
        found.setOutputS3Key("outputs/video/master.m3u8");
        found.setThumbnailS3Key("thumbnails/video.jpg");
        Video updated = repository.saveAndFlush(found);
        entityManager.clear();

        Video reloaded = repository.findById(updated.getId()).orElseThrow();
        assertThat(reloaded.getStatus()).isEqualTo(VideoStatus.COMPLETED);
        assertThat(reloaded.getOutputS3Key()).isEqualTo("outputs/video/master.m3u8");
        assertThat(reloaded.getThumbnailS3Key()).isEqualTo("thumbnails/video.jpg");
        assertThat(reloaded.getUpdatedAt()).isAfterOrEqualTo(reloaded.getCreatedAt());
    }
}
