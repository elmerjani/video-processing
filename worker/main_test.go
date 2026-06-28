package main

import (
	"context"
	"database/sql"
	"errors"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

type fakeResult struct {
	rows int64
}

func (r fakeResult) LastInsertId() (int64, error) { return 0, nil }
func (r fakeResult) RowsAffected() (int64, error) { return r.rows, nil }

type recordingExecer struct {
	query string
	args  []any
	rows  int64
	err   error
}

func (e *recordingExecer) ExecContext(_ context.Context, query string, args ...any) (sql.Result, error) {
	e.query = query
	e.args = args
	if e.err != nil {
		return nil, e.err
	}
	return fakeResult{rows: e.rows}, nil
}

func TestClaimJob(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		rows        int64
		wantClaimed bool
	}{
		{name: "wins atomic claim", rows: 1, wantClaimed: true},
		{name: "duplicate loses atomic claim", rows: 0, wantClaimed: false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			db := &recordingExecer{rows: tt.rows}
			claimed, err := claimJob(context.Background(), db, "job-1", "worker-1", "claim-1", 300)
			if err != nil {
				t.Fatalf("claimJob() error = %v, want nil", err)
			}
			if claimed != tt.wantClaimed {
				t.Fatalf("claimJob() claimed = %t, want %t", claimed, tt.wantClaimed)
			}
			if !strings.Contains(db.query, "status='QUEUED'") || !strings.Contains(db.query, "lease_expires_at <= now()") {
				t.Fatalf("claimJob() query is missing atomic claim predicates: %s", db.query)
			}
			if len(db.args) != 4 || db.args[0] != "job-1" || db.args[1] != "worker-1" || db.args[2] != "claim-1" || db.args[3] != int32(300) {
				t.Fatalf("claimJob() args = %#v, want job, worker, claim, lease", db.args)
			}
		})
	}
}

func TestNewClaimToken(t *testing.T) {
	t.Parallel()

	first, err := newClaimToken()
	if err != nil {
		t.Fatalf("newClaimToken() error = %v", err)
	}
	second, err := newClaimToken()
	if err != nil {
		t.Fatalf("newClaimToken() error = %v", err)
	}
	if len(first) != 32 || len(second) != 32 {
		t.Fatalf("claim token lengths = %d and %d, want 32", len(first), len(second))
	}
	if first == second {
		t.Fatal("newClaimToken() returned duplicate tokens")
	}
}

func TestJobMessageValidate(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		message JobMessage
		wantErr string
	}{
		{
			name: "valid",
			message: JobMessage{
				JobID:          "job-1",
				Bucket:         "videos",
				SourceS3Key:    "uploads/job-1/input.mov",
				OutputS3Key:    "outputs/job-1.mp4",
				ThumbnailS3Key: "thumbnails/job-1.jpg",
			},
		},
		{
			name:    "all fields missing",
			message: JobMessage{},
			wantErr: "message missing required fields: jobId, bucket, sourceS3Key, outputS3Key, thumbnailS3Key",
		},
		{
			name: "only source missing",
			message: JobMessage{
				JobID:          "job-1",
				Bucket:         "videos",
				OutputS3Key:    "outputs/job-1.mp4",
				ThumbnailS3Key: "thumbnails/job-1.jpg",
			},
			wantErr: "message missing required fields: sourceS3Key",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			err := tt.message.validate()
			if tt.wantErr == "" {
				if err != nil {
					t.Fatalf("validate() error = %v, want nil", err)
				}
				return
			}

			if err == nil {
				t.Fatal("validate() error = nil, want error")
			}
			if err.Error() != tt.wantErr {
				t.Fatalf("validate() error = %q, want %q", err.Error(), tt.wantErr)
			}
		})
	}
}

func TestJobMessageFromSQSBody(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name           string
		body           string
		fallbackBucket string
		want           JobMessage
		wantErr        string
	}{
		{
			name: "custom job message still works",
			body: `{
				"jobId":"job-1",
				"bucket":"videos",
				"sourceS3Key":"uploads/job-1/input.mov",
				"outputS3Key":"outputs/job-1/master.m3u8",
				"thumbnailS3Key":"thumbnails/job-1.jpg"
			}`,
			want: JobMessage{
				JobID:          "job-1",
				Bucket:         "videos",
				SourceS3Key:    "uploads/job-1/input.mov",
				OutputS3Key:    "outputs/job-1/master.m3u8",
				ThumbnailS3Key: "thumbnails/job-1.jpg",
			},
		},
		{
			name: "custom job message uses fallback bucket",
			body: `{
				"jobId":"job-1",
				"sourceS3Key":"uploads/job-1/input.mov",
				"outputS3Key":"outputs/job-1/master.m3u8",
				"thumbnailS3Key":"thumbnails/job-1.jpg"
			}`,
			fallbackBucket: "fallback-videos",
			want: JobMessage{
				JobID:          "job-1",
				Bucket:         "fallback-videos",
				SourceS3Key:    "uploads/job-1/input.mov",
				OutputS3Key:    "outputs/job-1/master.m3u8",
				ThumbnailS3Key: "thumbnails/job-1.jpg",
			},
		},
		{
			name: "s3 upload event becomes job message",
			body: `{
				"Records": [{
					"eventSource": "aws:s3",
					"s3": {
						"bucket": {"name": "videos"},
						"object": {"key": "uploads%2Fjob-1%2Fclip+1.mp4"}
					}
				}]
			}`,
			want: JobMessage{
				JobID:          "job-1",
				Bucket:         "videos",
				SourceS3Key:    "uploads/job-1/clip 1.mp4",
				OutputS3Key:    "outputs/job-1/master.m3u8",
				ThumbnailS3Key: "thumbnails/job-1.jpg",
			},
		},
		{
			name: "s3 output event is ignored",
			body: `{
				"Records": [{
					"eventSource": "aws:s3",
					"s3": {
						"bucket": {"name": "videos"},
						"object": {"key": "outputs%2Fjob-1%2Fmaster.m3u8"}
					}
				}]
			}`,
			wantErr: "S3 event has no uploads/ object record",
		},
		{
			name:    "s3 test event is ignored",
			body:    `{"Service":"Amazon S3","Event":"s3:TestEvent"}`,
			wantErr: "S3 event has no uploads/ object record",
		},
		{
			name:    "invalid json",
			body:    "{not-json",
			wantErr: "bad message JSON:",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, err := jobMessageFromSQSBody(tt.body, tt.fallbackBucket)
			if tt.wantErr == "" {
				if err != nil {
					t.Fatalf("jobMessageFromSQSBody() error = %v, want nil", err)
				}
				if got != tt.want {
					t.Fatalf("jobMessageFromSQSBody() = %#v, want %#v", got, tt.want)
				}
				return
			}

			if err == nil {
				t.Fatal("jobMessageFromSQSBody() error = nil, want error")
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Fatalf("jobMessageFromSQSBody() error = %q, want containing %q", err.Error(), tt.wantErr)
			}
		})
	}
}

func TestJobIDFromUploadKey(t *testing.T) {
	t.Parallel()

	got, err := jobIDFromUploadKey("uploads/123/source.mp4")
	if err != nil {
		t.Fatalf("jobIDFromUploadKey() error = %v, want nil", err)
	}
	if got != "123" {
		t.Fatalf("jobIDFromUploadKey() = %q, want 123", got)
	}

	for _, key := range []string{"uploads/", "uploads/job-only", "outputs/123/source.mp4"} {
		key := key
		t.Run(key, func(t *testing.T) {
			t.Parallel()

			if _, err := jobIDFromUploadKey(key); err == nil {
				t.Fatal("jobIDFromUploadKey() error = nil, want error")
			}
		})
	}
}

func TestHandleMessagePermanentValidationErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		body string
	}{
		{
			name: "invalid JSON",
			body: "{not-json",
		},
		{
			name: "missing required field after bucket fallback",
			body: `{"jobId":"job-1","sourceS3Key":"uploads/job-1/input.mov","outputS3Key":"outputs/job-1.mp4"}`,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			err := handleMessage(context.Background(), Config{VideoBucket: "videos"}, nil, nil, tt.body)
			if err == nil {
				t.Fatal("handleMessage() error = nil, want error")
			}

			var permanent permanentError
			if !errors.As(err, &permanent) {
				t.Fatalf("handleMessage() error type = %T, want permanentError", err)
			}
		})
	}
}

func TestApproximateReceiveCount(t *testing.T) {
	t.Parallel()

	key := string(sqstypes.MessageSystemAttributeNameApproximateReceiveCount)

	tests := []struct {
		name       string
		attributes map[string]string
		want       int
	}{
		{name: "missing defaults to one", attributes: nil, want: 1},
		{name: "invalid defaults to one", attributes: map[string]string{key: "abc"}, want: 1},
		{name: "zero defaults to one", attributes: map[string]string{key: "0"}, want: 1},
		{name: "valid", attributes: map[string]string{key: "4"}, want: 4},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			if got := approximateReceiveCount(tt.attributes); got != tt.want {
				t.Fatalf("approximateReceiveCount() = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestPostgresURL(t *testing.T) {
	t.Parallel()

	got := postgresURL("video_app", "p@ss/word", "db.example.com", "5432", "videoprocessing", "require")
	parsed, err := url.Parse(got)
	if err != nil {
		t.Fatalf("postgresURL() produced invalid URL: %v", err)
	}

	if parsed.Scheme != "postgres" {
		t.Fatalf("scheme = %q, want postgres", parsed.Scheme)
	}
	if parsed.User.Username() != "video_app" {
		t.Fatalf("username = %q, want video_app", parsed.User.Username())
	}
	password, ok := parsed.User.Password()
	if !ok || password != "p@ss/word" {
		t.Fatalf("password = %q ok=%v, want p@ss/word true", password, ok)
	}
	if parsed.Host != "db.example.com:5432" {
		t.Fatalf("host = %q, want db.example.com:5432", parsed.Host)
	}
	if parsed.Path != "/videoprocessing" {
		t.Fatalf("path = %q, want /videoprocessing", parsed.Path)
	}
	if parsed.Query().Get("sslmode") != "require" {
		t.Fatalf("sslmode = %q, want require", parsed.Query().Get("sslmode"))
	}
}

func TestSecretAndStringHelpers(t *testing.T) {
	t.Parallel()

	secret := map[string]any{
		"username": "video_app",
		"port":     float64(5432),
		"enabled":  true,
		"nil":      nil,
	}

	if got := stringFromSecret(secret, "username"); got != "video_app" {
		t.Fatalf("stringFromSecret(username) = %q, want video_app", got)
	}
	if got := stringFromSecret(secret, "port"); got != "5432" {
		t.Fatalf("stringFromSecret(port) = %q, want 5432", got)
	}
	if got := stringFromSecret(secret, "enabled"); got != "true" {
		t.Fatalf("stringFromSecret(enabled) = %q, want true", got)
	}
	if got := stringFromSecret(secret, "nil"); got != "" {
		t.Fatalf("stringFromSecret(nil) = %q, want empty", got)
	}
	if got := stringFromSecret(secret, "missing"); got != "" {
		t.Fatalf("stringFromSecret(missing) = %q, want empty", got)
	}

	if got := firstNonEmpty("", "", "database-host", "fallback"); got != "database-host" {
		t.Fatalf("firstNonEmpty() = %q, want database-host", got)
	}
}

func TestTruncate(t *testing.T) {
	t.Parallel()

	if got := truncate("short", 10); got != "short" {
		t.Fatalf("truncate(short, 10) = %q, want short", got)
	}

	got := truncate("abcdef", 3)
	if got != "abc" {
		t.Fatalf("truncate(abcdef, 3) = %q, want abc", got)
	}

	long := strings.Repeat("x", 2000)
	if got := truncate(long, 1900); len(got) != 1900 {
		t.Fatalf("truncate(long, 1900) length = %d, want 1900", len(got))
	}
}

func TestSelectRenditions(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		info       VideoInfo
		wantLabels []string
		wantWidths []int
	}{
		{
			name:       "full HD gets all variants",
			info:       VideoInfo{Width: 1920, Height: 1080},
			wantLabels: []string{"360p", "480p", "720p", "1080p"},
			wantWidths: []int{640, 854, 1280, 1920},
		},
		{
			name:       "720p input is not upscaled",
			info:       VideoInfo{Width: 1280, Height: 720},
			wantLabels: []string{"360p", "480p", "720p"},
			wantWidths: []int{640, 854, 1280},
		},
		{
			name:       "small input gets source-height variant",
			info:       VideoInfo{Width: 426, Height: 240},
			wantLabels: []string{"240p"},
			wantWidths: []int{426},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got := selectRenditions(tt.info)
			if len(got) != len(tt.wantLabels) {
				t.Fatalf("selectRenditions() length = %d, want %d: %#v", len(got), len(tt.wantLabels), got)
			}

			for i := range got {
				if got[i].Label != tt.wantLabels[i] {
					t.Fatalf("rendition[%d].Label = %q, want %q", i, got[i].Label, tt.wantLabels[i])
				}
				if got[i].Width != tt.wantWidths[i] {
					t.Fatalf("rendition[%d].Width = %d, want %d", i, got[i].Width, tt.wantWidths[i])
				}
				if got[i].Height%2 != 0 || got[i].Width%2 != 0 {
					t.Fatalf("rendition[%d] dimensions are not even: %dx%d", i, got[i].Width, got[i].Height)
				}
			}
		})
	}
}

func TestHLSMasterS3Key(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		message JobMessage
		want    string
	}{
		{
			name: "keeps playlist key from API",
			message: JobMessage{
				JobID:       "job-1",
				OutputS3Key: "outputs/job-1/master.m3u8",
			},
			want: "outputs/job-1/master.m3u8",
		},
		{
			name: "converts legacy mp4 key to job HLS prefix",
			message: JobMessage{
				JobID:       "job-1",
				OutputS3Key: "outputs/job-1.mp4",
			},
			want: "outputs/job-1/master.m3u8",
		},
		{
			name: "falls back from arbitrary output key",
			message: JobMessage{
				OutputS3Key: "outputs/custom.mp4",
			},
			want: "outputs/custom/master.m3u8",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			if got := hlsMasterS3Key(tt.message); got != tt.want {
				t.Fatalf("hlsMasterS3Key() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestContentTypeForPath(t *testing.T) {
	t.Parallel()

	tests := map[string]string{
		"master.m3u8":      "application/vnd.apple.mpegurl",
		"segment_00001.ts": "video/mp2t",
		"output.mp4":       "video/mp4",
		"thumbnail.jpg":    "image/jpeg",
		"unknown.bin":      "application/octet-stream",
	}

	for path, want := range tests {
		path := path
		want := want
		t.Run(path, func(t *testing.T) {
			t.Parallel()

			if got := contentTypeForPath(path); got != want {
				t.Fatalf("contentTypeForPath(%q) = %q, want %q", path, got, want)
			}
		})
	}
}

func TestWriteMasterPlaylist(t *testing.T) {
	t.Parallel()

	path := filepath.Join(t.TempDir(), "master.m3u8")
	renditions := []Rendition{
		{Label: "360p", Width: 640, Height: 360, Bandwidth: 950000},
		{Label: "720p", Width: 1280, Height: 720, Bandwidth: 3200000},
	}

	if err := writeMasterPlaylist(path, renditions); err != nil {
		t.Fatalf("writeMasterPlaylist() error = %v", err)
	}

	gotBytes, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read master playlist: %v", err)
	}

	got := string(gotBytes)
	for _, want := range []string{
		"#EXTM3U\n",
		"#EXT-X-STREAM-INF:BANDWIDTH=950000,RESOLUTION=640x360\n360p/index.m3u8\n",
		"#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1280x720\n720p/index.m3u8\n",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("master playlist missing %q in:\n%s", want, got)
		}
	}
}
