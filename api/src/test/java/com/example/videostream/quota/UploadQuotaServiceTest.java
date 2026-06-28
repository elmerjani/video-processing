package com.example.videostream.quota;

import com.example.videostream.video.persistence.VideoRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UploadQuotaServiceTest {

    @Mock
    private NamedParameterJdbcTemplate jdbc;

    @Mock
    private VideoRepository videoRepository;

    private UploadQuotaService service;

    @BeforeEach
    void setUp() {
        service = new UploadQuotaService(jdbc, videoRepository);
        ReflectionTestUtils.setField(service, "maxActiveJobs", 3);
        ReflectionTestUtils.setField(service, "maxDailyJobs", 20);
        ReflectionTestUtils.setField(service, "maxDailyBytes", 5_368_709_120L);
    }

    @SuppressWarnings("unchecked")
    @Test
    void reservesQuotaWhenDailyAndActiveLimitsPermitIt() {
        when(jdbc.query(anyString(), any(SqlParameterSource.class), any(ResultSetExtractor.class)))
                .thenReturn(1);
        when(videoRepository.countByOwnerIdAndStatusIn(anyString(), any())).thenReturn(2L);

        assertThatCode(() -> service.reserve("user-1", 1024L)).doesNotThrowAnyException();
    }

    @SuppressWarnings("unchecked")
    @Test
    void rejectsExhaustedDailyQuota() {
        when(jdbc.query(anyString(), any(SqlParameterSource.class), any(ResultSetExtractor.class)))
                .thenReturn(null);

        assertThatThrownBy(() -> service.reserve("user-1", 1024L))
                .isInstanceOf(UploadQuotaExceededException.class)
                .hasMessage("Daily upload quota exceeded");
    }

    @SuppressWarnings("unchecked")
    @Test
    void rejectsTooManyActiveJobs() {
        when(jdbc.query(anyString(), any(SqlParameterSource.class), any(ResultSetExtractor.class)))
                .thenReturn(1);
        when(videoRepository.countByOwnerIdAndStatusIn(anyString(), any())).thenReturn(3L);

        assertThatThrownBy(() -> service.reserve("user-1", 1024L))
                .isInstanceOf(UploadQuotaExceededException.class)
                .hasMessage("Too many active video jobs");
    }
}
