package com.example.videostream.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;

import java.time.Clock;

@Configuration
public class AwsConfig {

    @Value("${app.aws.region}")
    private String region;

    @Bean
    public AwsCredentialsProvider awsCredentialsProvider() {
        return DefaultCredentialsProvider.create();
    }

    @Bean
    public Region awsRegion() {
        return Region.of(region);
    }

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
