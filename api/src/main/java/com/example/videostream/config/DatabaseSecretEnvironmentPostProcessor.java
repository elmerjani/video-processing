package com.example.videostream.config;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;

import java.util.HashMap;
import java.util.Map;

public class DatabaseSecretEnvironmentPostProcessor implements EnvironmentPostProcessor, Ordered {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        String secretArn = firstNonBlank(
                environment.getProperty("app.database.secret-arn"),
                environment.getProperty("DATABASE_SECRET_ARN")
        );

        if (secretArn == null) {
            return;
        }

        Map<String, Object> secret = readSecret(secretArn, resolveRegion(environment));
        String host = firstNonBlank(environment.getProperty("app.database.host"), stringValue(secret.get("host")));
        String port = firstNonBlank(environment.getProperty("app.database.port"), stringValue(secret.get("port")), "5432");
        String databaseName = firstNonBlank(
                environment.getProperty("app.database.name"),
                stringValue(secret.get("dbname")),
                stringValue(secret.get("database")),
                stringValue(secret.get("databaseName"))
        );
        String username = firstNonBlank(stringValue(secret.get("username")));
        String password = firstNonBlank(stringValue(secret.get("password")));
        String sslMode = firstNonBlank(environment.getProperty("app.database.sslmode"), "require");

        if (host == null || databaseName == null || username == null || password == null) {
            throw new IllegalStateException("Database secret must include host, username, password, and database name must be configured.");
        }

        Map<String, Object> properties = new HashMap<>();
        properties.put("spring.datasource.url", "jdbc:postgresql://" + host + ":" + port + "/" + databaseName + "?sslmode=" + sslMode);
        properties.put("spring.datasource.username", username);
        properties.put("spring.datasource.password", password);

        environment.getPropertySources().addFirst(new MapPropertySource("databaseSecret", properties));
    }

    @Override
    public int getOrder() {
        return Ordered.LOWEST_PRECEDENCE;
    }

    private static Region resolveRegion(ConfigurableEnvironment environment) {
        String region = firstNonBlank(
                environment.getProperty("app.aws.region"),
                environment.getProperty("AWS_REGION"),
                environment.getProperty("AWS_DEFAULT_REGION"),
                "eu-central-1"
        );
        return Region.of(region);
    }

    private static Map<String, Object> readSecret(String secretArn, Region region) {
        try (SecretsManagerClient client = SecretsManagerClient.builder()
                .region(region)
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build()) {
            String secretString = client.getSecretValue(GetSecretValueRequest.builder()
                    .secretId(secretArn)
                    .build()).secretString();

            if (secretString == null || secretString.isBlank()) {
                throw new IllegalStateException("Database secret does not contain a secret string.");
            }

            return OBJECT_MAPPER.readValue(secretString, new TypeReference<>() {
            });
        } catch (Exception e) {
            throw new IllegalStateException("Failed to load database credentials from Secrets Manager.", e);
        }
    }

    private static String stringValue(Object value) {
        return value == null ? null : value.toString();
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return null;
    }
}
