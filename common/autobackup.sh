#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Backup Worker (autobackup.sh)
# ==============================================================================
#
# Description:
#   This script is executed by cron to perform the core backup logic. It is
#   designed to be stateless and configurable entirely via environment variables.
#
#   The process is as follows:
#   1. Create a temporary folder for the backup.
#   2. Copy specified directories into the backup folder.
#   3. Dump a PostgreSQL database into the backup folder.
#   4. Archive the entire backup folder into a single .tar.gz file.
#   5. Upload the archive to the configured S3-compatible provider.
#   6. Ping a health check URL to notify monitoring services of success or failure.
#
# --- REQUIRED ENVIRONMENT VARIABLES ---
#   (These are validated by the entrypoint but are listed here for clarity)
#   - S3_PROVIDER: 'aws', 'cloudflare', 'minio', etc.
#   - BUCKET_NAME: The name of the S3 bucket.
#   - AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
#   - DATABASE_NAME, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST
#   - DIRECTORIES_TO_BACKUP: A space-separated list of paths to back up.
#
# --- OPTIONAL ENVIRONMENT VARIABLES ---
#   - BACKUP_PATH_PREFIX: A folder path within the bucket to store backups
#                         (e.g., "production/web-server").
#   - AWS_S3_ENDPOINT_URL: Required for any non-AWS S3 provider.
#   - RCLONE_FLAGS: Extra flags to pass to the `rclone copyto` command.
#                   (e.g., "--s3-storage-class=STANDARD_IA --retries=5").
#   
#
# ==============================================================================

set -euo pipefail

# --- Globals and Logging ---
RCLONE_CONFIG_FILE=""
BACKUP_ARCHIVE_FILE=""
log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] [BACKUP] $*"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] [BACKUP] $*" >&2; }

# --- Cleanup & Health Check Function ---
# This function is now more powerful. It pings a health check URL on exit.
cleanup() {
  local exit_code=$? # Capture the exit code of the last command.
  set +e # Disable exit on error for the cleanup block.

  log_info "Executing local file cleanup..."
  rm -f "$RCLONE_CONFIG_FILE" "$BACKUP_ARCHIVE_FILE" || true
  if [[ -n "$BACKUP_ARCHIVE_FILE" ]]; then
    rm -rf "${BACKUP_ARCHIVE_FILE%.tar.gz}" || true
  fi
  log_info "Cleanup finished."
  # Exit with the original exit code.
  exit $exit_code
}
trap cleanup EXIT

# --- Main Logic ---
main() {
  log_info "Starting S3 backup process for database '${DATABASE_NAME}'"

  # === 1. Prepare Backup Files ===
  cd /tmp
  local timestamp
  timestamp=$(date -u +'%Y-%m-%dT%H-%M-%SZ')
  local backup_folder="${DATABASE_NAME}_backup_${timestamp}"
  mkdir -p "$backup_folder"

  log_info "Backing up directories: ${DIRECTORIES_TO_BACKUP}"
  local dirs_to_backup_array=()
  read -r -a dirs_to_backup_array <<< "$DIRECTORIES_TO_BACKUP"
  for dir_path in "${dirs_to_backup_array[@]}"; do
    if [ -d "$dir_path" ]; then
        # Using rsync is slightly more robust than cp -a for complex permissions.
        rsync -a "$dir_path" "$backup_folder/"
    else
        log_info "Skipping missing directory: $dir_path"
    fi
  done

  # log_info "Dumping PostgreSQL database..."
  # export PGPASSWORD="$POSTGRES_PASSWORD"
  # # Add improved error handling for pg_dump
  # if ! pg_dump --format=custom -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$DATABASE_NAME" > "${backup_folder}/${DATABASE_NAME}.dump"; then
  #   log_error "pg_dump failed. Check database credentials and connectivity."
  #   # The trap will handle the exit and health check ping.
  #   exit 1
  # fi
  # unset PGPASSWORD
  # log_info "Database dump completed."

  log_info "Dumping database '${DATABASE_NAME}'..."
  # This script will be provided by the specific Dockerfile (pg14, pg17, mysql, etc.).
  if ! /usr/local/bin/perform-db-dump > "${backup_folder}/${DATABASE_NAME}.dump"; then
    log_error "Database dump failed. Check database logs and credentials."
    exit 1
  fi
  log_info "Database dump completed."


  BACKUP_ARCHIVE_FILE="/tmp/${backup_folder}.tar.gz"
  tar -czf "$BACKUP_ARCHIVE_FILE" "$backup_folder"
  log_info "Archive created: ${BACKUP_ARCHIVE_FILE}"

  # === 2. Generate Rclone Config ===
  RCLONE_CONFIG_FILE=$(mktemp /tmp/rclone.XXXXXX)
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

  # === 3. Format Destination Path and Upload ===
  local path_components=()
  if [[ -n "${BACKUP_PATH_PREFIX:-}" ]]; then
      path_components+=("$(echo "${BACKUP_PATH_PREFIX}" | sed 's:^/*::;s:/*$::')")
  fi
  path_components+=("${DATABASE_NAME}")

  local remote_folder_path
  remote_folder_path=$(IFS=/; echo "${path_components[*]}")
  local remote_dest="s3_remote:${BUCKET_NAME}/${remote_folder_path}/$(basename "$BACKUP_ARCHIVE_FILE")"
  log_info "Uploading to: ${remote_dest}"

  # Define default flags and allow user to override/add more.
  # Note: The user-provided flags are word-split, so they should be formatted correctly.
  local rclone_flags_array=()
  read -r -a rclone_flags_array <<< "${RCLONE_FLAGS:-}"
  
  if ! rclone --config "$RCLONE_CONFIG_FILE" copyto "$BACKUP_ARCHIVE_FILE" "$remote_dest" \
      --s3-upload-concurrency=4 \
      --s3-chunk-size=64M \
      --s3-no-check-bucket \
      --progress \
      "${rclone_flags_array[@]}"; then
      log_error "Rclone upload failed."
      exit 1
  fi

  log_info "Upload successful. Backup process completed."
  # The trap will handle the final successful health check ping.
}

main "$@"