package com.example.videostream.upload;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

class S3UploadUrlSignerTest {

    @Test
    void createsSignedPostPolicyWithExactSizeAndContentType() throws Exception {
        ObjectMapper objectMapper = new ObjectMapper();
        S3UploadUrlSigner signer = new S3UploadUrlSigner(
                StaticCredentialsProvider.create(AwsBasicCredentials.create("access-key", "secret-key")),
                Region.US_EAST_1,
                Clock.fixed(Instant.parse("2026-06-27T12:00:00Z"), ZoneOffset.UTC));
        ReflectionTestUtils.setField(signer, "uploadUrlExpirationMinutes", 10L);

        PresignedUpload upload = signer.sign(
                "videos-bucket",
                "uploads/job-1/clip.mp4",
                "video/mp4",
                1024L);

        assertThat(upload.method()).isEqualTo("POST");
        assertThat(upload.url()).isEqualTo("https://videos-bucket.s3.us-east-1.amazonaws.com/");
        assertThat(upload.expiresAt()).isEqualTo(Instant.parse("2026-06-27T12:10:00Z"));
        assertThat(upload.fields())
                .containsEntry("key", "uploads/job-1/clip.mp4")
                .containsEntry("Content-Type", "video/mp4")
                .containsKey("policy")
                .containsKey("x-amz-signature");

        byte[] policyJson = Base64.getDecoder().decode(upload.fields().get("policy"));
        JsonNode policy = objectMapper.readTree(policyJson);
        assertThat(policy.get("expiration").asText()).isEqualTo("2026-06-27T12:10:00Z");
        assertThat(policy.get("conditions").toString())
                .contains("content-length-range")
                .contains("1024")
                .contains("video/mp4");
    }
}
