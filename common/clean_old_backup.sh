#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Cleanup Worker (clean_old_backups.sh)
# ==============================================================================
#
# Description:
#   This script is executed by cron to clean up old backups from the remote
#   S3 storage, enforcing the data retention policy.
#
#   Its logic for path creation and S3 provider configuration is designed to
#   be an exact mirror of `autobackup.sh` to ensure it targets the correct
#   directory for cleanup.
#
# --- REQUIRED ENVIRONMENT VARIABLES ---
#   (These are validated by the entrypoint but are listed here for clarity)
#   - S3_PROVIDER: 'aws', 'cloudflare', 'minio', etc.
#   - BUCKET_NAME: The name of the S3 bucket.
#   - DATABASE_NAME: Used to construct the path to the backup directory.
#   - NUMBER_OF_DAYS: The age at which backups will be deleted (e.g., 15).
#
# --- OPTIONAL ENVIRONMENT VARIABLES ---
#   - BACKUP_PATH_PREFIX: A folder path within the bucket, must match autobackup.sh.
#   - HEALTHCHECK_URL: A URL to ping on success/failure (supports Healthchecks.io).
#   - DRY_RUN: If set to "true", will run the command without deleting any files,
#              showing what *would* have been deleted. A crucial safety feature.
#
# ==============================================================================

set -euo pipefail

# --- Globals and Logging ---
RCLONE_CONFIG_FILE=""
log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] [CLEANUP] $*"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] [CLEANUP] $*" >&2; }

# --- Cleanup & Health Check Function ---
cleanup() {
  local exit_code=$?
  set +e # Disable exit on error for this block

  log_info "Executing local file cleanup..."
  rm -f "$RCLONE_CONFIG_FILE" || true
  log_info "Cleanup finished."
  exit $exit_code
}
trap cleanup EXIT

# --- Main Logic ---
main() {
  log_info "Starting old backup cleanup process..."

  # === 1. Generate Rclone Config ===
  RCLONE_CONFIG_FILE=$(mktemp /tmp/rclone_cleanup.XXXXXX)
  declare rclone_provider_value
  case "${S3_PROVIDER,,}" in
    aws)                rclone_provider_value="AWS" ;;
    cloudflare|r2)      rclone_provider_value="Other" ;;
    minio)              rclone_provider_value="Minio" ;;
    digitalocean)       rclone_provider_value="DigitalOcean" ;;
    *)                  rclone_provider_value="Other" ;;
  esac

  cat <<EOF > "$RCLONE_CONFIG_FILE"
[s3_remote]
type = s3
provider = ${rclone_provider_value}
access_key_id = ${AWS_ACCESS_KEY_ID}
secret_access_key = ${AWS_SECRET_ACCESS_KEY}
region = ${AWS_REGION}
endpoint = ${AWS_S3_ENDPOINT_URL:-}
acl = private
EOF

  # === 2. Format Target Path and Execute Cleanup ===
  local path_components=()
  if [[ -n "${BACKUP_PATH_PREFIX:-}" ]]; then
      path_components+=("$(echo "${BACKUP_PATH_PREFIX}" | sed 's:^/*::;s:/*$::')")
  fi
  path_components+=("${DATABASE_NAME}")

  local remote_folder_path
  remote_folder_path=$(IFS=/; echo "${path_components[*]}")
  local remote_path_to_clean="s3_remote:${BUCKET_NAME}/${remote_folder_path}/"

  # Add a --dry-run flag if the user requests it, a critical safety feature.
  local rclone_delete_flags=()
  if [[ "${DRY_RUN:-}" == "true" ]]; then
      log_info "Executing in DRY RUN mode. No files will be deleted."
      rclone_delete_flags+=("--dry-run")
  fi

  log_info "Deleting files older than ${NUMBER_OF_DAYS} days from '${remote_path_to_clean}'..."

  # The 'rclone delete' command with --min-age is perfect for this.
  if ! rclone --config "$RCLONE_CONFIG_FILE" delete "$remote_path_to_clean" \
      --min-age "${NUMBER_OF_DAYS}d" \
      "${rclone_delete_flags[@]}"; then
    log_error "Rclone cleanup command failed. Please check logs."
    exit 1
  fi

  log_info "Cleanup process completed successfully."
}

main "$@"