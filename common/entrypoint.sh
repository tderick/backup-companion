#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Entrypoint
# ==============================================================================
#
# Description:
#   This script is the main entrypoint for the Docker container. Its primary
#   responsibilities are:
#   1. Validate the environment configuration by sourcing `env.sh`.
#   2. Perform a LIVE connection test to the S3 provider to ensure credentials
#      and bucket access are correct BEFORE starting the main service.
#   3. If validation succeeds, it creates the cron jobs and captures all
#      environment variables for the cron daemon to use.
#   4. Starts the cron daemon in the foreground.
#
# --- Configuration: S3_PROVIDER ---
#
# The `S3_PROVIDER` environment variable tells the script how to configure
# rclone for your specific S3-compatible provider. Use one of the following
# exact values (case-insensitive):
#
#   - `aws`:
#     For Amazon Web Services S3.
#     Requires: `AWS_REGION`.
#     Endpoint URL must be empty.
#
#   - `cloudflare` or `r2`:
#     For Cloudflare R2 Storage.
#     Requires: `AWS_S3_ENDPOINT_URL`.
#
#   - `minio`:
#     For self-hosted Minio servers.
#     Requires: `AWS_REGION` and `AWS_S3_ENDPOINT_URL`.
#
#   - `digitalocean`:
#     For DigitalOcean Spaces.
#     Requires: `AWS_REGION` and `AWS_S3_ENDPOINT_URL`.
#
#   - Any other value (e.g., `wasabi`, `backblaze`, `scaleway`):
#     For any other S3-compatible provider. This will use a generic S3
#     configuration.
#     Requires: `AWS_REGION` and `AWS_S3_ENDPOINT_URL`.
#
# ==============================================================================

set -euo pipefail

echo "--- [entrypoint.sh] Starting container setup ---"

# 0. Validate environment variables by sourcing env.sh. If it fails, this script stops.
source /usr/local/bin/env.sh

# 1. Timezone configuration
TZ="${TZ:-UTC}"  # Default to UTC if TZ not set

if [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
  echo "--- [entrypoint.sh] Timezone set to: $TZ ---"
else
  echo "⚠️  Invalid TZ value '$TZ'. Falling back to UTC."
  ln -snf /usr/share/zoneinfo/UTC /etc/localtime
  echo "UTC" > /etc/timezone
fi

# 2. Perform S3 connection and bucket validation.
echo "--- [entrypoint.sh] Performing S3 connection test for bucket '${BUCKET_NAME}'... ---"
__rclone_config_file=$(mktemp /tmp/rclone_test.XXXXXX)
trap 'rm -f "$__rclone_config_file"' EXIT # Ensure cleanup

# Translate the user-friendly S3_PROVIDER name into the value rclone requires.
declare rclone_provider_value
case "${S3_PROVIDER,,}" in # Convert to lowercase for case-insensitivity
  aws)                rclone_provider_value="AWS" ;;
  cloudflare|r2)      rclone_provider_value="Other" ;;
  minio)              rclone_provider_value="Minio" ;;
  digitalocean)       rclone_provider_value="DigitalOcean" ;;
  *)                  rclone_provider_value="Other" ;;
esac
echo "--- [entrypoint.sh] Using rclone provider value: '${rclone_provider_value}' ---"

# Generate a temporary rclone config for the test.
cat <<EOF > "$__rclone_config_file"
[s3_remote]
type = s3
provider = ${rclone_provider_value}
access_key_id = ${AWS_ACCESS_KEY_ID}
secret_access_key = ${AWS_SECRET_ACCESS_KEY}
region = ${AWS_REGION}
endpoint = ${AWS_S3_ENDPOINT_URL:-}
acl = private
EOF

# Use `rclone size` to verify credentials AND access to the specific bucket. Fails fast.
if ! rclone --config "$__rclone_config_file" size "s3_remote:${BUCKET_NAME}"; then
    echo "--- [entrypoint.sh] CRITICAL: Rclone connection test failed! ---"
    echo "Could not access bucket '${BUCKET_NAME}'. Check credentials, region, endpoint, and bucket permissions."
    echo "The container will now exit."
    exit 1
fi
echo "--- [entrypoint.sh] Rclone S3 connection test successful. ---"

# 3. Set up cron jobs and environment
echo "--- [entrypoint.sh] Setting up cron jobs... ---"
mkdir -p /var/log/backup
CRON_SCHEDULE_BACKUP="${CRON_SCHEDULE_BACKUP:-0 1 * * *}"
CRON_SCHEDULE_CLEAN="${CRON_SCHEDULE_CLEAN:-0 2 * * *}"

cat <<EOF > /etc/cron.d/backup_jobs
# Pipe cron job output to the container's stdout/stderr for easy logging.
$CRON_SCHEDULE_BACKUP root . /etc/container_environment.sh; /usr/local/bin/autobackup.sh > /proc/1/fd/1 2>/proc/1/fd/2
$CRON_SCHEDULE_CLEAN root . /etc/container_environment.sh; /usr/local/bin/clean_old_backup.sh > /proc/1/fd/1 2>/proc/1/fd/2
EOF
chmod 0644 /etc/cron.d/backup_jobs


# 4. Capture all environment variables for the cron jobs to use.
{
  while IFS='=' read -r -d '' key value; do
    printf "export %s='%s'\n" "$key" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
  done < /proc/self/environ
} > /etc/container_environment.sh

echo "--- [entrypoint.sh] Setup complete. Starting cron daemon... ---"

# 5. Start cron daemon in the foreground.
exec crond -f -s