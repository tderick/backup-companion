#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Cleanup Worker (clean_old_backups.sh)
# ==============================================================================
#
# Description:
#   This script is executed by cron to clean up old backups from remote S3
#   storage, enforcing the data retention policy for each defined backup group.
#
#   Its logic for deriving the backup path for each group is an exact mirror
#   of `autobackup.sh` to ensure it targets the correct directories.
#
# --- REQUIRED ENVIRONMENT VARIABLES ---
#   - DATABASES & DIRECTORIES_TO_BACKUP: Used to identify all backup groups.
#   - NUMBER_OF_DAYS: The age (in days) at which backups will be deleted.
#   - S3_PROVIDER, BUCKET_NAME, etc. (for rclone config)
#
# --- OPTIONAL ENVIRONMENT VARIABLES ---
#   - BACKUP_PATH_PREFIX: A folder path within the bucket, must match autobackup.sh.
#   - DRY_RUN: If set to "true", will show what *would* be deleted without
#              actually deleting anything. A crucial safety feature.
#
# ==============================================================================

set -euo pipefail

# Define a script name for logging and source the shared library
readonly SCRIPT_NAME="AUTOCLEANUP"
RCLONE_CONFIG_FILE=""
source /usr/local/bin/lib.sh

# Set up the shared exit trap.
setup_exit_trap

# ==============================================================================
# FUNCTION: perform_cleanup_for_group
#
# Performs the cleanup for a single application group's backup directory.
#
# Arguments:
#   $1: The database group string (e.g., "db1:... db2:..." or "NONE")
#   $2: The directory group string (e.g., "/path/1:/path/2" or "NONE")
# ==============================================================================
perform_cleanup_for_group() {
  local db_group="$1"
  local dir_group="$2"

  # === 1. Determine the Backup ID for the group (MUST MATCH autobackup.sh) ===
  local backup_id=""
  if [[ "$db_group" != "NONE" ]]; then
      local first_db_conn; read -r first_db_conn _ <<< "$db_group"
      IFS=':' read -r backup_id _ <<< "$first_db_conn"
  elif [[ "$dir_group" != "NONE" ]]; then
      local first_dir_path; IFS=':' read -r first_dir_path _ <<< "$dir_group"
      backup_id=$(basename "$first_dir_path" | tr -c '[:alnum:]_.-' '_')
  else
      # This case is validated in env.sh, but we check again for safety.
      log_error "Skipping cleanup for empty group (both databases and directories are NONE)."
      return 0 # Not a failure, just nothing to do.
  fi
  log_info "--- Cleaning up old backups for application group '${backup_id}' ---"

  # === 2. Construct the Remote Path to Clean ===
  local path_components=()
  if [[ -n "${BACKUP_PATH_PREFIX:-}" ]]; then
      path_components+=("$(echo "${BACKUP_PATH_PREFIX}" | sed 's:^/*::;s:/*$::')")
  fi
  path_components+=("${backup_id}")

  local remote_folder_path; remote_folder_path=$(IFS=/; echo "${path_components[*]}")
  local remote_path_to_clean="s3_remote:${BUCKET_NAME}/${remote_folder_path}/"

  # === 3. Execute the Cleanup Command ===
  local rclone_delete_flags=()
  if [[ "${DRY_RUN:-}" == "true" ]]; then
      log_info "Executing in DRY RUN mode for group '${backup_id}'. No files will be deleted."
      rclone_delete_flags+=("--dry-run")
  fi

  log_info "Deleting files older than ${NUMBER_OF_DAYS} days from '${remote_path_to_clean}'..."

  if ! rclone --config "$RCLONE_CONFIG_FILE" delete "$remote_path_to_clean" \
      --min-age "${NUMBER_OF_DAYS}d" \
      "${rclone_delete_flags[@]}"; then
    log_error "Rclone cleanup command failed for group '${backup_id}'."
    return 1
  fi

  log_info "Cleanup for group '${backup_id}' completed successfully."
}

# --- Main Logic ---
main() {
  log_info "Starting old backup cleanup orchestrator..."

  # === 1. Validate Configuration ===
  : "${DATABASES:?FATAL: DATABASES environment variable is not set.}"
  : "${DIRECTORIES_TO_BACKUP:?FATAL: DIRECTORIES_TO_BACKUP environment variable is not set.}"
  : "${NUMBER_OF_DAYS:?FATAL: NUMBER_OF_DAYS environment variable is required.}"

  read -r -a db_groups <<< "$DATABASES"
  read -r -a dir_groups <<< "$DIRECTORIES_TO_BACKUP"

  if [ ${#db_groups[@]} -ne ${#dir_groups[@]} ]; then
    log_error "Configuration error: Group counts in DATABASES and DIRECTORIES_TO_BACKUP do not match."
    exit 1
  fi
  log_info "Found ${#db_groups[@]} application group(s) to clean."

  # === 2. Generate Rclone Config Once ===
  RCLONE_CONFIG_FILE=$(mktemp /tmp/rclone_cleanup.XXXXXX)
  generate_rclone_config "$RCLONE_CONFIG_FILE"

  # === 3. Loop Through All Groups and Perform Cleanup ===
  local total_groups=${#db_groups[@]}
  local failed_groups=0

  for i in "${!db_groups[@]}"; do
    if ! perform_cleanup_for_group "${db_groups[$i]}" "${dir_groups[$i]}"; then
      log_error "A failure occurred during the cleanup of group #$((i+1)). Continuing with the next group."
      failed_groups=$((failed_groups + 1))
    fi
  done
  
  log_info "Cleanup job finished. Total groups processed: ${total_groups}. Failed groups: ${failed_groups}."
  
  if [ "$failed_groups" -gt 0 ]; then
    log_error "One or more cleanup groups failed. Please check the logs."
    exit 1
  fi
}

main "$@"