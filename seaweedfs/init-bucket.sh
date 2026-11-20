#!/bin/sh
# Creates the Loki bucket on SeaweedFS with Object Lock (WORM) enabled and a
# default retention, plus default server-side encryption. Idempotent: safe
# to run against an already-initialized bucket.
#
# Required env: S3_ENDPOINT, BUCKET_NAME, RETENTION_MODE (GOVERNANCE or
# COMPLIANCE), RETENTION_DAYS, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
set -eu

AWS="aws --endpoint-url ${S3_ENDPOINT}"

echo "Waiting for SeaweedFS S3 API at ${S3_ENDPOINT}..."
i=0
until ${AWS} s3api list-buckets >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then
    echo "SeaweedFS S3 API did not come up in time" >&2
    exit 1
  fi
  sleep 2
done

if ${AWS} s3api head-bucket --bucket "${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Bucket ${BUCKET_NAME} already exists, skipping creation."
else
  echo "Creating bucket ${BUCKET_NAME} with Object Lock enabled..."
  ${AWS} s3api create-bucket --bucket "${BUCKET_NAME}" --object-lock-enabled-for-bucket

  echo "Setting default retention: ${RETENTION_MODE} / ${RETENTION_DAYS} days..."
  ${AWS} s3api put-object-lock-configuration --bucket "${BUCKET_NAME}" --object-lock-configuration "{
    \"ObjectLockEnabled\": \"Enabled\",
    \"Rule\": {
      \"DefaultRetention\": {
        \"Mode\": \"${RETENTION_MODE}\",
        \"Days\": ${RETENTION_DAYS}
      }
    }
  }"
fi

echo "Setting default bucket encryption (SSE-S3)..."
${AWS} s3api put-bucket-encryption --bucket "${BUCKET_NAME}" --server-side-encryption-configuration '{
  "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
}'

echo "SeaweedFS bucket ${BUCKET_NAME} ready."
