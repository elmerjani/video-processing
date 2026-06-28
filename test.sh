#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_VIDEO_FILE="$HOME/Downloads/test_video.mp4"
VIDEO_FILE="${1:-$DEFAULT_VIDEO_FILE}"
BASE_URL="${BASE_URL:-}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"
TEST_USER_EMAIL="${TEST_USER_EMAIL:-video-processing-test@example.com}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-}"
COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:-}"
COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID:-}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
POLL_SECONDS="${POLL_SECONDS:-10}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-120}"

CREATE_BODY="$(mktemp -t video-create.XXXXXX)"
UPLOAD_BODY="$(mktemp -t video-upload.XXXXXX)"
STATUS_BODY="$(mktemp -t video-status.XXXXXX)"
trap 'rm -f "$CREATE_BODY" "$UPLOAD_BODY" "$STATUS_BODY"' EXIT

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Video file not found: $VIDEO_FILE" >&2
    echo "Usage: $0 /path/to/video.mp4" >&2
    exit 1
fi

if [ -z "$BASE_URL" ]; then
    if ! command -v terraform >/dev/null 2>&1; then
        echo "terraform is required to read the deployed API URL; alternatively set BASE_URL" >&2
        exit 1
    fi
    BASE_URL="$(terraform -chdir="$ROOT_DIR/infra/envs/dev" output -raw api_gateway_invoke_url)"
fi

if [ -z "$ACCESS_TOKEN" ]; then
    for command in aws terraform openssl; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "$command is required to create and authenticate the Cognito test user" >&2
            exit 1
        fi
    done

    if [ -z "$COGNITO_USER_POOL_ID" ]; then
        COGNITO_USER_POOL_ID="$(terraform -chdir="$ROOT_DIR/infra/envs/dev" output -raw cognito_user_pool_id)"
    fi
    if [ -z "$COGNITO_CLIENT_ID" ]; then
        COGNITO_CLIENT_ID="$(terraform -chdir="$ROOT_DIR/infra/envs/dev" output -raw cognito_client_id)"
    fi
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION="${COGNITO_USER_POOL_ID%%_*}"
    fi
    if [ -z "$TEST_USER_PASSWORD" ]; then
        TEST_USER_PASSWORD="VideoTest!$(openssl rand -hex 12)aA1"
    fi

    echo "Preparing Cognito test user: $TEST_USER_EMAIL"
    if ! aws cognito-idp admin-get-user \
        --region "$AWS_REGION" \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --username "$TEST_USER_EMAIL" >/dev/null 2>&1; then
        aws cognito-idp admin-create-user \
            --region "$AWS_REGION" \
            --user-pool-id "$COGNITO_USER_POOL_ID" \
            --username "$TEST_USER_EMAIL" \
            --user-attributes \
                "Name=email,Value=$TEST_USER_EMAIL" \
                "Name=email_verified,Value=true" \
            --message-action SUPPRESS >/dev/null
    fi

    aws cognito-idp admin-set-user-password \
        --region "$AWS_REGION" \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --username "$TEST_USER_EMAIL" \
        --password "$TEST_USER_PASSWORD" \
        --permanent

    AUTH_RESPONSE="$(aws cognito-idp initiate-auth \
        --region "$AWS_REGION" \
        --client-id "$COGNITO_CLIENT_ID" \
        --auth-flow USER_PASSWORD_AUTH \
        --auth-parameters "USERNAME=$TEST_USER_EMAIL,PASSWORD=$TEST_USER_PASSWORD")"
    ACCESS_TOKEN="$(printf '%s' "$AUTH_RESPONSE" | jq -r '.AuthenticationResult.AccessToken // empty')"

    if [ -z "$ACCESS_TOKEN" ]; then
        echo "Cognito authentication did not return an access token" >&2
        exit 1
    fi
    echo "Cognito access token obtained."
fi

BASE_URL="${BASE_URL%/}"
CONTENT_TYPE="$(file --mime-type -b "$VIDEO_FILE" 2>/dev/null || true)"
CONTENT_TYPE="${CONTENT_TYPE:-video/mp4}"

case "$CONTENT_TYPE" in
    video/mp4|video/quicktime|video/webm) ;;
    *)
        echo "Unsupported content type: $CONTENT_TYPE" >&2
        echo "Allowed types: video/mp4, video/quicktime, video/webm" >&2
        exit 1
        ;;
esac

if FILE_SIZE="$(stat -f%z "$VIDEO_FILE" 2>/dev/null)"; then
    :
elif FILE_SIZE="$(stat -c%s "$VIDEO_FILE" 2>/dev/null)"; then
    :
else
    echo "Unable to determine video file size" >&2
    exit 1
fi

echo "API: $BASE_URL"
echo "Video: $VIDEO_FILE"
echo "Content-Type: $CONTENT_TYPE"
echo "Size: $FILE_SIZE bytes"

echo "Creating video..."
CREATE_STATUS="$(curl -sS -o "$CREATE_BODY" -w '%{http_code}' -X POST "$BASE_URL/videos" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
        --arg fileName "$(basename "$VIDEO_FILE")" \
        --arg contentType "$CONTENT_TYPE" \
        --argjson sizeBytes "$FILE_SIZE" \
        '{fileName: $fileName, contentType: $contentType, sizeBytes: $sizeBytes}')")"

CREATE_RESPONSE="$(cat "$CREATE_BODY")"
if [[ "$CREATE_STATUS" != 2* ]]; then
    echo "Create video failed with HTTP $CREATE_STATUS. Response:" >&2
    printf '%s\n' "$CREATE_RESPONSE" | jq . >&2 || printf '%s\n' "$CREATE_RESPONSE" >&2
    exit 1
fi

VIDEO_ID="$(printf '%s' "$CREATE_RESPONSE" | jq -r '.videoId // empty')"
UPLOAD_URL="$(printf '%s' "$CREATE_RESPONSE" | jq -r '.upload.url // empty')"
UPLOAD_METHOD="$(printf '%s' "$CREATE_RESPONSE" | jq -r '.upload.method // empty')"

if [ -z "$VIDEO_ID" ] || [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_METHOD" != "POST" ]; then
    echo "Create video failed. Response:" >&2
    printf '%s\n' "$CREATE_RESPONSE" | jq . >&2
    exit 1
fi

echo "Video ID: $VIDEO_ID"
echo "Uploading directly to S3 with the signed POST policy..."

FORM_ARGS=()
while IFS=$'\t' read -r field_name field_value; do
    FORM_ARGS+=(--form-string "$field_name=$field_value")
done < <(printf '%s' "$CREATE_RESPONSE" | jq -r '.upload.fields | to_entries[] | [.key, .value] | @tsv')

# The file must be part of the same multipart form as every signed field.
FORM_ARGS+=(-F "file=@${VIDEO_FILE};type=${CONTENT_TYPE}")

UPLOAD_STATUS="$(curl -sS -o "$UPLOAD_BODY" -w '%{http_code}' \
    -X POST "$UPLOAD_URL" \
    "${FORM_ARGS[@]}")"

if [[ "$UPLOAD_STATUS" != 2* ]]; then
    echo "S3 upload failed with HTTP $UPLOAD_STATUS. Response:" >&2
    cat "$UPLOAD_BODY" >&2
    exit 1
fi

echo "Upload complete (HTTP $UPLOAD_STATUS). Polling status..."

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    STATUS_HTTP="$(curl -sS -o "$STATUS_BODY" -w '%{http_code}' \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$BASE_URL/videos/$VIDEO_ID")"
    STATUS_RESPONSE="$(cat "$STATUS_BODY")"

    if [[ "$STATUS_HTTP" != 2* ]]; then
        echo "Status request failed with HTTP $STATUS_HTTP. Response:" >&2
        printf '%s\n' "$STATUS_RESPONSE" | jq . >&2 || printf '%s\n' "$STATUS_RESPONSE" >&2
        exit 1
    fi

    STATUS="$(printf '%s' "$STATUS_RESPONSE" | jq -r '.status // empty')"

    printf '[%s/%s] %s\n' "$attempt" "$MAX_ATTEMPTS" "$STATUS"
    printf '%s\n' "$STATUS_RESPONSE" | jq .

    if [ "$STATUS" = "COMPLETED" ]; then
        echo "Completed."
        echo "HLS key: $(printf '%s' "$STATUS_RESPONSE" | jq -r '.hlsS3Key')"
        echo "Thumbnail key: $(printf '%s' "$STATUS_RESPONSE" | jq -r '.thumbnailS3Key')"
        exit 0
    fi

    if [ "$STATUS" = "FAILED" ]; then
        echo "Video processing failed." >&2
        exit 1
    fi

    sleep "$POLL_SECONDS"
done

echo "Timed out waiting for video $VIDEO_ID after $MAX_ATTEMPTS attempts." >&2
exit 1
