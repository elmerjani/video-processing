package com.example.videostream;

import com.example.videostream.upload.UploadUrlSigner;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.security.oauth2.jwt.JwtDecoder;

@SpringBootTest(properties = {
		"spring.datasource.url=jdbc:h2:mem:videostream;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
		"spring.datasource.driver-class-name=org.h2.Driver",
		"spring.datasource.username=sa",
		"spring.datasource.password=",
		"spring.flyway.enabled=false",
		"spring.jpa.hibernate.ddl-auto=create-drop",
		"spring.security.oauth2.resourceserver.jwt.issuer-uri=https://issuer.example",
		"app.aws.cognito-client-id=test-client"
})
class VideoStreamApplicationTests {

	@MockitoBean
	private UploadUrlSigner uploadUrlSigner;

	@MockitoBean
	private JwtDecoder jwtDecoder;

	@Test
	void contextLoads() {
	}

}
