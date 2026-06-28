package com.example.videostream.video.persistence;

import com.example.videostream.video.domain.Video;
import com.example.videostream.video.domain.VideoStatus;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.Optional;
import java.util.UUID;

public interface VideoRepository extends JpaRepository<Video, UUID> {
    Optional<Video> findByIdAndOwnerId(UUID id, String ownerId);
    long countByOwnerIdAndStatusIn(String ownerId, Collection<VideoStatus> statuses);
}
