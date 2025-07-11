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

#!/bin/bash
set -euo pipefail

# Define a script name for logging purposes, then source the shared library.
readonly SCRIPT_NAME="ENTRYPOINT"
source /usr/local/bin/lib.sh

# --- Helper Functions (Specific to entrypoint.sh) ---
test_s3_connection() {
  log_info "Performing S3 connection test for bucket '${BUCKET_NAME}'..."
  local temp_config
  temp_config=$(mktemp /tmp/rclone_test.XXXXXX)
  trap 'rm -f "$temp_config"' RETURN

  # <<< The key change is here: calling the shared function >>>
  generate_rclone_config "$temp_config"

  if ! rclone --config "$temp_config" size "s3_remote:${BUCKET_NAME}"; then
      log_error "CRITICAL: Rclone connection test failed!"
      exit 1
  fi
  log_info "Rclone S3 connection test successful."
}

# Sets the container's timezone based on the TZ environment variable.
setup_timezone() {
  log_info "Configuring timezone..."
  local tz="${TZ:-UTC}" # Default to UTC if TZ is not set

  if [ -f "/usr/share/zoneinfo/$tz" ]; then
    ln -snf "/usr/share/zoneinfo/$tz" /etc/localtime
    echo "$tz" > /etc/timezone
    log_info "Timezone set to: $tz"
  else
    log_error "Invalid TZ value '$tz'. Falling back to UTC."
    ln -snf /usr/share/zoneinfo/UTC /etc/localtime
    echo "UTC" > /etc/timezone
  fi
}

#
# Creates cron jobs and captures the current environment for them to use.
#
setup_cron() {
  log_info "Setting up cron jobs..."

  # 1. Save all environment variables to a file that cron can source.
  # This is the most reliable way to pass the environment to cron jobs.
  {
    while IFS='=' read -r -d '' key value; do
      # Escape single quotes in the value for safe shell execution.
      printf "export %s='%s'\n" "$key" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
    done < /proc/self/environ
  } > /etc/container_environment.sh

  # 2. Create the cron job definitions.
  cat <<EOF > /etc/cron.d/s3_backup_jobs
# Pipe cron job output to the container's stdout/stderr for easy logging via `docker logs`.
${CRON_SCHEDULE_BACKUP} root . /etc/container_environment.sh; /usr/local/bin/autobackup.sh > /proc/1/fd/1 2>/proc/1/fd/2
${CRON_SCHEDULE_CLEAN} root . /etc/container_environment.sh; /usr/local/bin/clean_old_backup.sh > /proc/1/fd/1 2>/proc/1/fd/2
EOF

  chmod 0644 /etc/cron.d/s3_backup_jobs
  log_info "Cron jobs created and environment captured."
}

# --- Main Execution ---
main() {
  log_info "Container setup started."
  source /usr/local/bin/env.sh
  setup_timezone
  test_s3_connection
  setup_cron
  log_info "Setup complete. Starting cron daemon..."
  exec crond -f  -s
}

main "$@"
