package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"math"
	"net"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	s3path "path"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	_ "github.com/jackc/pgx/v5/stdlib"
)

type Config struct {
	Region                   string
	QueueURL                 string
	VideoBucket              string
	DatabaseSecretARN        string
	DatabaseHost             string
	DatabasePort             string
	DatabaseName             string
	DatabaseSSLMode          string
	VisibilityTimeoutSeconds int32
	MaxReceiveCount          int
	ReceiveWaitSeconds       int32
	WorkerID                 string
}

type JobMessage struct {
	JobID          string `json:"jobId"`
	Bucket         string `json:"bucket"`
	SourceS3Key    string `json:"sourceS3Key"`
	OutputS3Key    string `json:"outputS3Key"`
	ThumbnailS3Key string `json:"thumbnailS3Key"`
}

type s3EventNotification struct {
	Records []s3EventRecord `json:"Records"`
}

type s3EventRecord struct {
	EventSource string `json:"eventSource"`
	S3          struct {
		Bucket struct {
			Name string `json:"name"`
		} `json:"bucket"`
		Object struct {
			Key string `json:"key"`
		} `json:"object"`
	} `json:"s3"`
}

type permanentError struct {
	err error
}

type jobBusyError struct {
	jobID  string
	status string
}

type claimedJobError struct {
	jobID      string
	claimToken string
	err        error
}

type VideoInfo struct {
	Width  int
	Height int
}

type Rendition struct {
	Label        string
	Width        int
	Height       int
	VideoBitrate string
	MaxRate      string
	BufferSize   string
	AudioBitrate string
	Bandwidth    int
}

type sqlExecer interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

var renditionLadder = []Rendition{
	{Label: "360p", Height: 360, VideoBitrate: "800k", MaxRate: "856k", BufferSize: "1200k", AudioBitrate: "96k", Bandwidth: 950000},
	{Label: "480p", Height: 480, VideoBitrate: "1400k", MaxRate: "1498k", BufferSize: "2100k", AudioBitrate: "128k", Bandwidth: 1600000},
	{Label: "720p", Height: 720, VideoBitrate: "2800k", MaxRate: "2996k", BufferSize: "4200k", AudioBitrate: "128k", Bandwidth: 3200000},
	{Label: "1080p", Height: 1080, VideoBitrate: "5000k", MaxRate: "5350k", BufferSize: "7500k", AudioBitrate: "192k", Bandwidth: 5500000},
}

func (e permanentError) Error() string {
	return e.err.Error()
}

func (e permanentError) Unwrap() error {
	return e.err
}

func (e jobBusyError) Error() string {
	return fmt.Sprintf("job %s is not claimable (status=%s)", e.jobID, e.status)
}

func (e claimedJobError) Error() string { return e.err.Error() }
func (e claimedJobError) Unwrap() error { return e.err }

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg := loadConfig()

	awsCfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(cfg.Region))
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)
	s3Client := s3.NewFromConfig(awsCfg)
	secretsClient := secretsmanager.NewFromConfig(awsCfg)

	db, err := openDB(ctx, cfg, secretsClient)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()

	log.Printf("worker started region=%s queue=%s visibility_timeout=%ds", cfg.Region, cfg.QueueURL, cfg.VisibilityTimeoutSeconds)

	for ctx.Err() == nil {
		resp, err := sqsClient.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:                    &cfg.QueueURL,
			MaxNumberOfMessages:         1,
			WaitTimeSeconds:             cfg.ReceiveWaitSeconds,
			VisibilityTimeout:           cfg.VisibilityTimeoutSeconds,
			MessageSystemAttributeNames: []sqstypes.MessageSystemAttributeName{sqstypes.MessageSystemAttributeNameApproximateReceiveCount},
		})
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Printf("receive message: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}

		for _, msg := range resp.Messages {
			if msg.Body == nil || msg.ReceiptHandle == nil {
				log.Printf("received malformed SQS message without body or receipt handle")
				continue
			}

			stopExtender := make(chan struct{})
			go extendMessageVisibility(ctx, sqsClient, cfg.QueueURL, *msg.ReceiptHandle, cfg.VisibilityTimeoutSeconds, stopExtender)

			err := handleMessage(ctx, cfg, db, s3Client, *msg.Body)
			close(stopExtender)

			if err != nil {
				var busy jobBusyError
				if errors.As(err, &busy) {
					log.Printf("duplicate or premature delivery; leaving message for retry: %v", err)
					continue
				}

				receiveCount := approximateReceiveCount(msg.Attributes)
				shouldDelete := false

				var permanent permanentError
				if errors.As(err, &permanent) {
					log.Printf("permanent job failure: %v", err)
					shouldDelete = markFailedFromMessage(ctx, db, cfg.VideoBucket, *msg.Body, err)
				} else if receiveCount >= cfg.MaxReceiveCount {
					log.Printf("job failed after %d receives: %v", receiveCount, err)
					shouldDelete = markFailedFromMessage(ctx, db, cfg.VideoBucket, *msg.Body, err)
				} else {
					log.Printf("job failed, leaving message for retry receive_count=%d: %v", receiveCount, err)
				}

				if !shouldDelete {
					continue
				}
			}

			if err := deleteMessage(ctx, sqsClient, cfg.QueueURL, *msg.ReceiptHandle); err != nil {
				log.Printf("delete message: %v", err)
			}
		}
	}

	log.Println("worker stopped")
}

func loadConfig() Config {
	visibilityTimeoutSeconds := int32(getenvInt("WORKER_VISIBILITY_TIMEOUT_SECONDS", 3600))
	return Config{
		Region:                   getenv("AWS_REGION", "us-east-1"),
		QueueURL:                 mustGetenv("VIDEO_JOBS_QUEUE_URL"),
		VideoBucket:              mustGetenv("VIDEO_BUCKET"),
		DatabaseSecretARN:        mustGetenv("DATABASE_SECRET_ARN"),
		DatabaseHost:             os.Getenv("DATABASE_HOST"),
		DatabasePort:             getenv("DATABASE_PORT", "5432"),
		DatabaseName:             getenv("DATABASE_NAME", "videoprocessing"),
		DatabaseSSLMode:          getenv("DATABASE_SSLMODE", "require"),
		VisibilityTimeoutSeconds: visibilityTimeoutSeconds,
		MaxReceiveCount:          getenvInt("WORKER_MAX_RECEIVE_COUNT", 3),
		ReceiveWaitSeconds:       int32(getenvInt("WORKER_RECEIVE_WAIT_SECONDS", 20)),
		WorkerID:                 getenv("WORKER_ID", defaultWorkerID()),
	}
}

func handleMessage(ctx context.Context, cfg Config, db *sql.DB, s3Client *s3.Client, body string) (retErr error) {
	jm, err := jobMessageFromSQSBody(body, cfg.VideoBucket)
	if err != nil {
		return permanentError{err: err}
	}

	var ownedClaimToken string
	defer func() {
		if retErr != nil && ownedClaimToken != "" {
			retErr = claimedJobError{jobID: jm.JobID, claimToken: ownedClaimToken, err: retErr}
		}
	}()

	claimToken, err := newClaimToken()
	if err != nil {
		return fmt.Errorf("generate claim token: %w", err)
	}

	claimed, err := claimJob(ctx, db, jm.JobID, cfg.WorkerID, claimToken, cfg.VisibilityTimeoutSeconds)
	if err != nil {
		return fmt.Errorf("claim job: %w", err)
	}
	if !claimed {
		status, err := currentJobStatus(ctx, db, jm.JobID)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return permanentError{err: fmt.Errorf("job %s not found", jm.JobID)}
			}
			return fmt.Errorf("read unclaimed job status: %w", err)
		}
		if status == "COMPLETED" {
			log.Printf("job already completed job_id=%s", jm.JobID)
			return nil
		}
		return jobBusyError{jobID: jm.JobID, status: status}
	}
	ownedClaimToken = claimToken

	stopLeaseExtender := make(chan struct{})
	go extendJobLease(ctx, db, jm.JobID, claimToken, cfg.VisibilityTimeoutSeconds, stopLeaseExtender)
	defer close(stopLeaseExtender)

	tmpDir, err := os.MkdirTemp("", "video-job-*")
	if err != nil {
		return fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	inputPath := filepath.Join(tmpDir, "input")
	hlsDir := filepath.Join(tmpDir, "hls")
	thumbPath := filepath.Join(tmpDir, "thumbnail.jpg")
	masterS3Key := hlsMasterS3Key(jm)
	hlsS3Prefix := s3path.Dir(masterS3Key)

	log.Printf("downloading source job_id=%s bucket=%s key=%s", jm.JobID, jm.Bucket, jm.SourceS3Key)
	if err := downloadFromS3(ctx, s3Client, jm.Bucket, jm.SourceS3Key, inputPath); err != nil {
		return fmt.Errorf("download source: %w", err)
	}

	log.Printf("processing video job_id=%s", jm.JobID)
	if err := runFFmpeg(ctx, inputPath, hlsDir, thumbPath); err != nil {
		return permanentError{err: err}
	}

	log.Printf("uploading HLS output job_id=%s master=%s thumbnail=%s", jm.JobID, masterS3Key, jm.ThumbnailS3Key)
	if err := uploadDirectoryToS3(ctx, s3Client, jm.Bucket, hlsDir, hlsS3Prefix); err != nil {
		return fmt.Errorf("upload HLS output: %w", err)
	}
	if err := uploadToS3(ctx, s3Client, jm.Bucket, jm.ThumbnailS3Key, thumbPath, "image/jpeg"); err != nil {
		return fmt.Errorf("upload thumbnail: %w", err)
	}

	if err := markCompleted(ctx, db, jm.JobID, claimToken, masterS3Key, jm.ThumbnailS3Key); err != nil {
		return fmt.Errorf("mark completed: %w", err)
	}

	log.Printf("job completed job_id=%s", jm.JobID)
	return nil
}

func (m JobMessage) validate() error {
	missing := make([]string, 0)
	if m.JobID == "" {
		missing = append(missing, "jobId")
	}
	if m.Bucket == "" {
		missing = append(missing, "bucket")
	}
	if m.SourceS3Key == "" {
		missing = append(missing, "sourceS3Key")
	}
	if m.OutputS3Key == "" {
		missing = append(missing, "outputS3Key")
	}
	if m.ThumbnailS3Key == "" {
		missing = append(missing, "thumbnailS3Key")
	}
	if len(missing) > 0 {
		return fmt.Errorf("message missing required fields: %s", strings.Join(missing, ", "))
	}
	return nil
}

func jobMessageFromSQSBody(body, fallbackBucket string) (JobMessage, error) {
	var jm JobMessage
	if err := json.Unmarshal([]byte(body), &jm); err != nil {
		return JobMessage{}, fmt.Errorf("bad message JSON: %w", err)
	}

	if jm.hasCustomJobFields() {
		if jm.Bucket == "" {
			jm.Bucket = fallbackBucket
		}
		if err := jm.validate(); err != nil {
			return JobMessage{}, err
		}
		return jm, nil
	}

	var event s3EventNotification
	if err := json.Unmarshal([]byte(body), &event); err != nil {
		return JobMessage{}, fmt.Errorf("bad S3 event JSON: %w", err)
	}
	return jobMessageFromS3Event(event, fallbackBucket)
}

func (m JobMessage) hasCustomJobFields() bool {
	return m.JobID != "" ||
		m.Bucket != "" ||
		m.SourceS3Key != "" ||
		m.OutputS3Key != "" ||
		m.ThumbnailS3Key != ""
}

func jobMessageFromS3Event(event s3EventNotification, fallbackBucket string) (JobMessage, error) {
	for _, record := range event.Records {
		if record.EventSource != "" && record.EventSource != "aws:s3" {
			continue
		}

		bucket := firstNonEmpty(record.S3.Bucket.Name, fallbackBucket)
		if bucket == "" || record.S3.Object.Key == "" {
			continue
		}

		key, err := url.QueryUnescape(record.S3.Object.Key)
		if err != nil {
			return JobMessage{}, fmt.Errorf("decode S3 object key: %w", err)
		}
		if !strings.HasPrefix(key, "uploads/") {
			continue
		}

		jobID, err := jobIDFromUploadKey(key)
		if err != nil {
			return JobMessage{}, err
		}
		return JobMessage{
			JobID:          jobID,
			Bucket:         bucket,
			SourceS3Key:    key,
			OutputS3Key:    "outputs/" + jobID + "/master.m3u8",
			ThumbnailS3Key: "thumbnails/" + jobID + ".jpg",
		}, nil
	}

	return JobMessage{}, fmt.Errorf("S3 event has no uploads/ object record")
}

func jobIDFromUploadKey(key string) (string, error) {
	if !strings.HasPrefix(key, "uploads/") {
		return "", fmt.Errorf("S3 upload key %q must match uploads/{jobId}/{fileName}", key)
	}
	rest := strings.TrimPrefix(key, "uploads/")
	parts := strings.SplitN(rest, "/", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", fmt.Errorf("S3 upload key %q must match uploads/{jobId}/{fileName}", key)
	}
	return parts[0], nil
}

func openDB(ctx context.Context, cfg Config, secretsClient *secretsmanager.Client) (*sql.DB, error) {
	secret, err := getDatabaseSecret(ctx, secretsClient, cfg.DatabaseSecretARN)
	if err != nil {
		return nil, err
	}

	username := stringFromSecret(secret, "username")
	password := stringFromSecret(secret, "password")
	host := firstNonEmpty(cfg.DatabaseHost, stringFromSecret(secret, "host"))
	port := firstNonEmpty(cfg.DatabasePort, stringFromSecret(secret, "port"))
	dbName := firstNonEmpty(cfg.DatabaseName, stringFromSecret(secret, "dbname"))

	if username == "" || password == "" || host == "" || port == "" || dbName == "" {
		return nil, fmt.Errorf("database secret/config is missing username, password, host, port, or dbname")
	}

	dsn := postgresURL(username, password, host, port, dbName, cfg.DatabaseSSLMode)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return nil, err
	}

	db.SetMaxOpenConns(2)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, err
	}

	return db, nil
}

func getDatabaseSecret(ctx context.Context, client *secretsmanager.Client, arn string) (map[string]any, error) {
	out, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: &arn,
	})
	if err != nil {
		return nil, fmt.Errorf("get database secret: %w", err)
	}
	if out.SecretString == nil {
		return nil, fmt.Errorf("database secret has no string value")
	}

	var secret map[string]any
	if err := json.Unmarshal([]byte(*out.SecretString), &secret); err != nil {
		return nil, fmt.Errorf("parse database secret JSON: %w", err)
	}
	return secret, nil
}

func currentJobStatus(ctx context.Context, db *sql.DB, jobID string) (string, error) {
	var status string
	err := db.QueryRowContext(ctx, `select status from video_jobs where id=$1`, jobID).Scan(&status)
	return status, err
}

func claimJob(ctx context.Context, db sqlExecer, jobID, workerID, claimToken string, leaseSeconds int32) (bool, error) {
	result, err := db.ExecContext(ctx,
		`update video_jobs
		 set status='PROCESSING',
		     worker_id=$2,
		     claim_token=$3,
		     lease_expires_at=now() + ($4::integer * interval '1 second'),
		     error_message=null,
		     updated_at=now()
		 where id=$1
		   and (
		     status='QUEUED'
		     or (
		       status='PROCESSING'
		       and (lease_expires_at is null or lease_expires_at <= now())
		     )
		   )`,
		jobID, workerID, claimToken, leaseSeconds,
	)
	if err != nil {
		return false, err
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return false, err
	}
	return rows == 1, nil
}

func markCompleted(ctx context.Context, db *sql.DB, jobID, claimToken, outputKey, thumbnailKey string) error {
	result, err := db.ExecContext(ctx,
		`update video_jobs
		 set status='COMPLETED',
		     output_s3_key=$3,
		     thumbnail_s3_key=$4,
		     error_message=null,
		     worker_id=null,
		     claim_token=null,
		     lease_expires_at=null,
		     updated_at=now()
		 where id=$1 and status='PROCESSING' and claim_token=$2`,
		jobID, claimToken, outputKey, thumbnailKey,
	)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows != 1 {
		return fmt.Errorf("job claim was lost before completion")
	}
	return nil
}

func markFailedFromMessage(ctx context.Context, db *sql.DB, fallbackBucket, body string, cause error) bool {
	var claimed claimedJobError
	if errors.As(cause, &claimed) {
		result, err := db.ExecContext(ctx,
			`update video_jobs
			 set status='FAILED',
			     error_message=$3,
			     worker_id=null,
			     claim_token=null,
			     lease_expires_at=null,
			     updated_at=now()
			 where id=$1 and status='PROCESSING' and claim_token=$2`,
			claimed.jobID,
			claimed.claimToken,
			truncate(cause.Error(), 1900),
		)
		if err != nil {
			log.Printf("mark failed job_id=%s: %v", claimed.jobID, err)
			return false
		}
		rows, err := result.RowsAffected()
		if err != nil {
			log.Printf("read mark failed result job_id=%s: %v", claimed.jobID, err)
			return false
		}
		if rows != 1 {
			log.Printf("not marking failed because job claim was lost job_id=%s", claimed.jobID)
			return false
		}
		return true
	}

	jm, err := jobMessageFromSQSBody(body, fallbackBucket)
	if err != nil || jm.JobID == "" {
		return true
	}

	_, err = db.ExecContext(ctx,
		`update video_jobs set status='FAILED', error_message=$2, updated_at=now() where id=$1`,
		jm.JobID,
		truncate(cause.Error(), 1900),
	)
	if err != nil {
		log.Printf("mark failed job_id=%s: %v", jm.JobID, err)
		return false
	}
	return true
}

func downloadFromS3(ctx context.Context, s3Client *s3.Client, bucket, key, outPath string) error {
	out, err := s3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: &bucket,
		Key:    &key,
	})
	if err != nil {
		return err
	}
	defer out.Body.Close()

	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, out.Body)
	return err
}

func uploadToS3(ctx context.Context, s3Client *s3.Client, bucket, key, path, contentType string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         &key,
		Body:        f,
		ContentType: &contentType,
	})
	return err
}

func uploadDirectoryToS3(ctx context.Context, s3Client *s3.Client, bucket, localDir, keyPrefix string) error {
	return filepath.WalkDir(localDir, func(localPath string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}

		relativePath, err := filepath.Rel(localDir, localPath)
		if err != nil {
			return err
		}

		key := s3path.Join(keyPrefix, filepath.ToSlash(relativePath))
		return uploadToS3(ctx, s3Client, bucket, key, localPath, contentTypeForPath(localPath))
	})
}

func runFFmpeg(ctx context.Context, inputPath, hlsDir, thumbPath string) error {
	info, err := probeVideo(ctx, inputPath)
	if err != nil {
		return err
	}

	renditions := selectRenditions(info)
	if len(renditions) == 0 {
		return fmt.Errorf("no renditions selected for input resolution %dx%d", info.Width, info.Height)
	}

	if err := os.MkdirAll(hlsDir, 0o755); err != nil {
		return fmt.Errorf("create HLS directory: %w", err)
	}

	for _, rendition := range renditions {
		if err := generateHLSRendition(ctx, inputPath, hlsDir, rendition); err != nil {
			return err
		}
	}

	if err := writeMasterPlaylist(filepath.Join(hlsDir, "master.m3u8"), renditions); err != nil {
		return err
	}

	thumbnail := exec.CommandContext(ctx,
		"ffmpeg",
		"-hide_banner",
		"-loglevel", "warning",
		"-y",
		"-ss", "00:00:01",
		"-i", inputPath,
		"-frames:v", "1",
		"-q:v", "2",
		thumbPath,
	)
	if out, err := thumbnail.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg thumbnail failed: %w output=%s", err, truncate(string(out), 1400))
	}

	return nil
}

func probeVideo(ctx context.Context, inputPath string) (VideoInfo, error) {
	cmd := exec.CommandContext(ctx,
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=width,height",
		"-of", "json",
		inputPath,
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return VideoInfo{}, fmt.Errorf("ffprobe failed: %w output=%s", err, truncate(string(out), 1400))
	}

	var response struct {
		Streams []VideoInfo `json:"streams"`
	}
	if err := json.Unmarshal(out, &response); err != nil {
		return VideoInfo{}, fmt.Errorf("parse ffprobe output: %w", err)
	}
	if len(response.Streams) == 0 || response.Streams[0].Width <= 0 || response.Streams[0].Height <= 0 {
		return VideoInfo{}, fmt.Errorf("ffprobe did not return a valid video stream")
	}

	return response.Streams[0], nil
}

func selectRenditions(info VideoInfo) []Rendition {
	selected := make([]Rendition, 0, len(renditionLadder))
	for _, candidate := range renditionLadder {
		if candidate.Height > info.Height {
			continue
		}

		rendition := candidate
		rendition.Width = scaledEvenWidth(info, candidate.Height)
		selected = append(selected, rendition)
	}

	if len(selected) > 0 {
		return selected
	}

	height := evenDown(info.Height)
	if height < 2 {
		height = 2
	}

	return []Rendition{
		{
			Label:        fmt.Sprintf("%dp", height),
			Width:        scaledEvenWidth(info, height),
			Height:       height,
			VideoBitrate: "500k",
			MaxRate:      "535k",
			BufferSize:   "750k",
			AudioBitrate: "96k",
			Bandwidth:    650000,
		},
	}
}

func generateHLSRendition(ctx context.Context, inputPath, hlsDir string, rendition Rendition) error {
	renditionDir := filepath.Join(hlsDir, rendition.Label)
	if err := os.MkdirAll(renditionDir, 0o755); err != nil {
		return fmt.Errorf("create rendition directory %s: %w", rendition.Label, err)
	}

	playlistPath := filepath.Join(renditionDir, "index.m3u8")
	segmentPattern := filepath.Join(renditionDir, "segment_%05d.ts")
	scaleFilter := fmt.Sprintf("scale=%d:%d:force_original_aspect_ratio=decrease:force_divisible_by=2", rendition.Width, rendition.Height)

	cmd := exec.CommandContext(ctx,
		"ffmpeg",
		"-hide_banner",
		"-loglevel", "warning",
		"-y",
		"-i", inputPath,
		"-map", "0:v:0",
		"-map", "0:a?",
		"-vf", scaleFilter,
		"-c:v", "libx264",
		"-preset", "veryfast",
		"-profile:v", "main",
		"-crf", "23",
		"-b:v", rendition.VideoBitrate,
		"-maxrate", rendition.MaxRate,
		"-bufsize", rendition.BufferSize,
		"-c:a", "aac",
		"-b:a", rendition.AudioBitrate,
		"-ac", "2",
		"-hls_time", "6",
		"-hls_playlist_type", "vod",
		"-hls_segment_filename", segmentPattern,
		playlistPath,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg HLS %s failed: %w output=%s", rendition.Label, err, truncate(string(out), 1400))
	}

	return nil
}

func writeMasterPlaylist(path string, renditions []Rendition) error {
	var builder strings.Builder
	builder.WriteString("#EXTM3U\n")
	builder.WriteString("#EXT-X-VERSION:3\n")

	for _, rendition := range renditions {
		builder.WriteString(fmt.Sprintf(
			"#EXT-X-STREAM-INF:BANDWIDTH=%d,RESOLUTION=%dx%d\n",
			rendition.Bandwidth,
			rendition.Width,
			rendition.Height,
		))
		builder.WriteString(fmt.Sprintf("%s/index.m3u8\n", rendition.Label))
	}

	return os.WriteFile(path, []byte(builder.String()), 0o644)
}

func scaledEvenWidth(info VideoInfo, targetHeight int) int {
	if info.Width <= 0 || info.Height <= 0 || targetHeight <= 0 {
		return 2
	}

	width := int(math.Round(float64(info.Width) * float64(targetHeight) / float64(info.Height)))
	return evenUp(width)
}

func evenDown(value int) int {
	if value < 2 {
		return 2
	}
	if value%2 == 0 {
		return value
	}
	return value - 1
}

func evenUp(value int) int {
	if value < 2 {
		return 2
	}
	if value%2 == 0 {
		return value
	}
	return value + 1
}

func hlsMasterS3Key(message JobMessage) string {
	if strings.HasSuffix(strings.ToLower(message.OutputS3Key), ".m3u8") {
		return message.OutputS3Key
	}
	if message.JobID != "" {
		return s3path.Join("outputs", message.JobID, "master.m3u8")
	}

	outputWithoutExt := strings.TrimSuffix(message.OutputS3Key, s3path.Ext(message.OutputS3Key))
	return s3path.Join(outputWithoutExt, "master.m3u8")
}

func contentTypeForPath(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".m3u8":
		return "application/vnd.apple.mpegurl"
	case ".ts":
		return "video/mp2t"
	case ".mp4":
		return "video/mp4"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	default:
		return "application/octet-stream"
	}
}

func extendMessageVisibility(ctx context.Context, client *sqs.Client, queueURL, receiptHandle string, timeoutSeconds int32, stop <-chan struct{}) {
	interval := time.Duration(timeoutSeconds) * time.Second / 2
	if interval < 30*time.Second {
		interval = 30 * time.Second
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-stop:
			return
		case <-ticker.C:
			_, err := client.ChangeMessageVisibility(ctx, &sqs.ChangeMessageVisibilityInput{
				QueueUrl:          &queueURL,
				ReceiptHandle:     &receiptHandle,
				VisibilityTimeout: timeoutSeconds,
			})
			if err != nil {
				log.Printf("extend message visibility: %v", err)
			}
		}
	}
}

func extendJobLease(ctx context.Context, db *sql.DB, jobID, claimToken string, leaseSeconds int32, stop <-chan struct{}) {
	interval := time.Duration(leaseSeconds) * time.Second / 2
	if interval < 30*time.Second {
		interval = 30 * time.Second
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-stop:
			return
		case <-ticker.C:
			result, err := db.ExecContext(ctx,
				`update video_jobs
				 set lease_expires_at=now() + ($3::integer * interval '1 second'),
				     updated_at=now()
				 where id=$1 and status='PROCESSING' and claim_token=$2`,
				jobID, claimToken, leaseSeconds,
			)
			if err != nil {
				log.Printf("extend job lease job_id=%s: %v", jobID, err)
				continue
			}
			rows, err := result.RowsAffected()
			if err != nil {
				log.Printf("read job lease update result job_id=%s: %v", jobID, err)
				continue
			}
			if rows != 1 {
				log.Printf("job lease lost job_id=%s", jobID)
				return
			}
		}
	}
}

func newClaimToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func defaultWorkerID() string {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "worker"
	}
	token, err := newClaimToken()
	if err != nil {
		token = strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	return fmt.Sprintf("%s:%d:%s", hostname, os.Getpid(), token)
}

func deleteMessage(ctx context.Context, client *sqs.Client, queueURL, receiptHandle string) error {
	_, err := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      &queueURL,
		ReceiptHandle: &receiptHandle,
	})
	return err
}

func approximateReceiveCount(attributes map[string]string) int {
	v := attributes[string(sqstypes.MessageSystemAttributeNameApproximateReceiveCount)]
	n, err := strconv.Atoi(v)
	if err != nil || n < 1 {
		return 1
	}
	return n
}

func postgresURL(username, password, host, port, dbName, sslMode string) string {
	u := url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(username, password),
		Host:   net.JoinHostPort(host, port),
		Path:   dbName,
	}
	q := u.Query()
	q.Set("sslmode", sslMode)
	u.RawQuery = q.Encode()
	return u.String()
}

func stringFromSecret(secret map[string]any, key string) string {
	value, ok := secret[key]
	if !ok || value == nil {
		return ""
	}

	switch typed := value.(type) {
	case string:
		return typed
	case float64:
		return strconv.FormatInt(int64(typed), 10)
	default:
		return fmt.Sprint(typed)
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func truncate(value string, max int) string {
	if len(value) <= max {
		return value
	}
	return value[:max]
}

func mustGetenv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		log.Fatalf("%s is required", key)
	}
	return value
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func getenvInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		log.Fatalf("%s must be an integer: %v", key, err)
	}
	return parsed
}
