package com.example.videostream.upload;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.AwsSessionCredentials;
import software.amazon.awssdk.regions.Region;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Component
public class S3UploadUrlSigner implements UploadUrlSigner {

    private static final String ALGORITHM = "AWS4-HMAC-SHA256";
    private static final DateTimeFormatter AMZ_DATE = DateTimeFormatter
            .ofPattern("yyyyMMdd'T'HHmmss'Z'")
            .withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter DATE_STAMP = DateTimeFormatter
            .ofPattern("yyyyMMdd")
            .withZone(ZoneOffset.UTC);

    private final AwsCredentialsProvider credentialsProvider;
    private final Region region;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Clock clock;

    @Value("${app.aws.upload-url-expiration-minutes:15}")
    private long uploadUrlExpirationMinutes;

    public S3UploadUrlSigner(
            AwsCredentialsProvider credentialsProvider,
            Region region,
            Clock clock
    ) {
        this.credentialsProvider = credentialsProvider;
        this.region = region;
        this.clock = clock;
    }

    @Override
    public PresignedUpload sign(String bucket, String key, String contentType, long sizeBytes) {
        AwsCredentials credentials = credentialsProvider.resolveCredentials();
        Instant now = clock.instant();
        Instant expiresAt = now.plus(Duration.ofMinutes(uploadUrlExpirationMinutes));
        String dateStamp = DATE_STAMP.format(now);
        String amzDate = AMZ_DATE.format(now);
        String credentialScope = dateStamp + "/" + region.id() + "/s3/aws4_request";
        String credential = credentials.accessKeyId() + "/" + credentialScope;

        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("key", key);
        fields.put("Content-Type", contentType);
        fields.put("x-amz-algorithm", ALGORITHM);
        fields.put("x-amz-credential", credential);
        fields.put("x-amz-date", amzDate);

        List<Object> conditions = new ArrayList<>();
        conditions.add(Map.of("bucket", bucket));
        conditions.add(Map.of("key", key));
        conditions.add(Map.of("Content-Type", contentType));
        conditions.add(Map.of("x-amz-algorithm", ALGORITHM));
        conditions.add(Map.of("x-amz-credential", credential));
        conditions.add(Map.of("x-amz-date", amzDate));
        conditions.add(List.of("content-length-range", sizeBytes, sizeBytes));

        if (credentials instanceof AwsSessionCredentials sessionCredentials) {
            fields.put("x-amz-security-token", sessionCredentials.sessionToken());
            conditions.add(Map.of("x-amz-security-token", sessionCredentials.sessionToken()));
        }

        String policy = encodePolicy(expiresAt, conditions);
        fields.put("policy", policy);
        fields.put("x-amz-signature", signature(credentials.secretAccessKey(), dateStamp, policy));

        String url = "https://" + bucket + ".s3." + region.id() + ".amazonaws.com/";
        return new PresignedUpload("POST", url, Map.copyOf(fields), expiresAt);
    }

    private String encodePolicy(Instant expiresAt, List<Object> conditions) {
        try {
            byte[] json = objectMapper.writeValueAsBytes(Map.of(
                    "expiration", expiresAt.toString(),
                    "conditions", conditions));
            return Base64.getEncoder().encodeToString(json);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to create S3 upload policy", exception);
        }
    }

    private String signature(String secretAccessKey, String dateStamp, String policy) {
        byte[] dateKey = hmac(("AWS4" + secretAccessKey).getBytes(StandardCharsets.UTF_8), dateStamp);
        byte[] regionKey = hmac(dateKey, region.id());
        byte[] serviceKey = hmac(regionKey, "s3");
        byte[] signingKey = hmac(serviceKey, "aws4_request");
        return HexFormat.of().formatHex(hmac(signingKey, policy));
    }

    private static byte[] hmac(byte[] key, String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to sign S3 upload policy", exception);
        }
    }
}
