#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Backup Worker (autobackup.sh)
# ==============================================================================
#
# Description:
#   This script is executed by cron to perform backups for one or more
#   "application groups". An application group is a collection of databases
#   and directories that are backed up together into a single archive.
#
#   This allows a single container instance to back up multiple distinct
#   applications, each to its own subdirectory in the S3 bucket.
#
# --- CONFIGURATION: BACKUP GROUPS ---
#
# The script works by mapping groups defined in DATABASES and
# DIRECTORIES_TO_BACKUP. Both variables must contain the same number of
# space-separated groups.
#
# - DATABASES: Space-separated groups of database connection strings.
#   - A group can contain multiple space-separated DBs.
#   - Use the keyword "NONE" if a group has no databases.
#   - Format: "db1:h1:p1:u1:p1 db2:h2:p2:u2:p2" "db3:h3:p3:u3:p3" "NONE"
#
# - DIRECTORIES_TO_BACKUP: Space-separated groups of directory paths.
#   - A group can contain multiple colon-separated (:) directory paths.
#   - Use the keyword "NONE" if a group has no directories.
#   - Format: "/var/www/app1:/etc/app1" "NONE" "/var/www/app3"
#
# EXAMPLE:
#   DATABASES="app1_db:host:5432:user:pass NONE"
#   DIRECTORIES_TO_BACKUP="/var/www/app1:/etc/nginx/app1 /var/log/app2"
#
#   This configuration defines two backup jobs:
#   1. Back up database 'app1_db' AND directories '/var/www/app1', '/etc/nginx/app1'.
#      The archive will be named based on 'app1_db'.
#   2. Back up ONLY the directory '/var/log/app2'. The archive will be named
#      based on 'app2'.
#
# --- OTHER REQUIRED VARIABLES ---
# - S3_PROVIDER, BUCKET_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
# - DB_DRIVER: 'postgres', 'mysql', or 'mariadb'. Applies to all DBs.
#
# ==============================================================================

set -euo pipefail

readonly SCRIPT_NAME="AUTOBACKUP"
RCLONE_CONFIG_FILE=""
source /usr/local/bin/lib.sh

# Set up the shared exit trap.
setup_exit_trap

# ==============================================================================
# FUNCTION: perform_group_backup
#
# Performs the entire backup process for a single application group.
#
# Arguments:
#   $1: The database group string (e.g., "db1:... db2:..." or "NONE")
#   $2: The directory group string (e.g., "/path/1:/path/2" or "NONE")
# ==============================================================================
perform_group_backup() {
  local db_group="$1"
  local dir_group="$2"
  
  # === 1. Determine the Backup ID for naming files and folders ===
  local backup_id=""
  if [[ "$db_group" != "NONE" ]]; then
      local first_db_conn
      read -r first_db_conn _ <<< "$db_group"
      IFS=':' read -r backup_id _ <<< "$first_db_conn"
  elif [[ "$dir_group" != "NONE" ]]; then
      local first_dir_path
      IFS=':' read -r first_dir_path _ <<< "$dir_group"
      backup_id=$(basename "$first_dir_path" | tr -c '[:alnum:]_.-' '_') # Sanitize name from path
  else
      log_error "Skipping empty backup group (both databases and directories are NONE)."
      return 1 # Return an error code for an invalid group.
  fi
  log_info "--- Starting backup for application group '${backup_id}' ---"

  # === 2. Prepare Temporary Backup Folder ===
  cd /tmp
  local timestamp
  timestamp=$(date +'%Y-%m-%dT%H-%M-%SZ')
  local backup_folder="${backup_id}_backup_${timestamp}"
  mkdir -p "$backup_folder"

  # === 3. Backup Directories for this Group ===
  if [[ "$dir_group" != "NONE" ]]; then
    log_info "Backing up directories for group '${backup_id}'..."
    # Replace colons with spaces to loop through paths
    local dir_list=${dir_group//:/ }
    for dir_path in $dir_list; do
      if [ -e "$dir_path" ]; then
        log_info "  - Adding: $dir_path"
        rsync -a "$dir_path" "$backup_folder/"
      else
        log_info "  - Skipping missing file/directory: $dir_path"
      fi
    done
  fi

  # === 4. Backup Databases for this Group ===
  if [[ "$db_group" != "NONE" ]]; then
    log_info "Backing up databases for group '${backup_id}'..."
    
    # Determine which dump script to use based on the global DB_DRIVER
    declare dump_script_path=""
    case "${DB_DRIVER,,}" in
      postgres)
        dump_script_path="/usr/local/bin/perform-db-dump.pg"
        ;;
      mysql|mariadb)
        dump_script_path="/usr/local/bin/perform-db-dump.mysql"
        ;;
      *)
        log_error "Unsupported DB_DRIVER '${DB_DRIVER}' for group '${backup_id}'. Skipping database backups."
        # We 'return 1' to mark the whole group as failed if the driver is invalid
        return 1
        ;;
    esac

    if [ ! -x "$dump_script_path" ]; then
        log_error "Dump script '${dump_script_path}' not found or not executable. Skipping database backups for group '${backup_id}'."
        return 1
    fi

    # Loop through each database in the group
    for db_string in $db_group; do
      IFS=':' read -r db_name db_host db_port db_user db_password <<< "$db_string"
      
      log_info "  - Dumping database '${db_name}'..."
      
      # Export credentials in a subshell to isolate them for this specific command.
      # This is the cleanest and safest way to handle credentials per-iteration.
      (
        case "${DB_DRIVER,,}" in
          postgres)
            export PGHOST="$db_host"
            export PGPORT="$db_port"
            export PGUSER="$db_user"
            export PGPASSWORD="$db_password"
            ;;
          mysql|mariadb)
            export MYSQL_HOST="$db_host"
            export MYSQL_PORT="$db_port"
            export MYSQL_USER="$db_user"
            export MYSQL_PASSWORD="$db_password"
            ;;
        esac
        
        # Execute the selected dump script with the db_name as an argument.
        "$dump_script_path" "$db_name"
      ) > "${backup_folder}/${db_name}.dump"

      # Check the exit code of the subshell
      if [ $? -ne 0 ]; then
        log_error "Database dump for '${db_name}' failed!"
        rm -rf "$backup_folder" # Clean up this group's partial backup
        return 1 # Mark the entire group as failed
      fi
    done
  fi
  
  # === 5. Archive, Upload, and Cleanup ===
  local backup_archive_file="/tmp/${backup_folder}.tar.gz"
  tar -czf "$backup_archive_file" "$backup_folder"
  log_info "Archive created: ${backup_archive_file}"

  local path_components=()
  if [[ -n "${BACKUP_PATH_PREFIX:-}" ]]; then
      path_components+=("$(echo "${BACKUP_PATH_PREFIX}" | sed 's:^/*::;s:/*$::')")
  fi
  path_components+=("${backup_id}") # Use the group ID for the subfolder in S3

  local remote_folder_path
  remote_folder_path=$(IFS=/; echo "${path_components[*]}")
  local remote_dest="s3_remote:${BUCKET_NAME}/${remote_folder_path}/$(basename "$backup_archive_file")"
  log_info "Uploading to: ${remote_dest}"

  local rclone_flags_array=()
  read -r -a rclone_flags_array <<< "${RCLONE_FLAGS:-}"
  
  if ! rclone --config "$RCLONE_CONFIG_FILE" copyto "$backup_archive_file" "$remote_dest" \
      --s3-upload-concurrency=4 --s3-chunk-size=64M --s3-no-check-bucket --progress \
      "${rclone_flags_array[@]}"; then
      log_error "Rclone upload for group '${backup_id}' failed."
      rm -rf "$backup_folder" "$backup_archive_file"
      return 1
  fi

  log_info "Cleaning up local files for group '${backup_id}'..."
  rm -rf "$backup_folder" "$backup_archive_file"
  log_info "--- Backup for application group '${backup_id}' complete. ---"
}


# --- Main Logic ---
main() {
  log_info "Starting S3 backup job orchestrator..."

  # === 1. Validate Configuration ===
  : "${DATABASES:?FATAL: DATABASES environment variable is not set.}"
  : "${DIRECTORIES_TO_BACKUP:?FATAL: DIRECTORIES_TO_BACKUP environment variable is not set.}"
  : "${DB_DRIVER:?FATAL: DB_DRIVER is required (e.g., 'postgres', 'mysql').}"

  # Read space-separated groups into arrays
  read -r -a db_groups <<< "$DATABASES"
  read -r -a dir_groups <<< "$DIRECTORIES_TO_BACKUP"

  if [ ${#db_groups[@]} -ne ${#dir_groups[@]} ]; then
    log_error "Configuration error: The number of groups in DATABASES (${#db_groups[@]}) does not match the number of groups in DIRECTORIES_TO_BACKUP (${#dir_groups[@]})."
    exit 1
  fi
  log_info "Found ${#db_groups[@]} application group(s) to back up."

  # === 2. Generate Rclone Config Once using the shared library function ===
  RCLONE_CONFIG_FILE=$(mktemp /tmp/rclone.XXXXXX)
  generate_rclone_config "$RCLONE_CONFIG_FILE"

  # === 3. Loop Through All Groups and Perform Backups ===
  local total_groups=${#db_groups[@]}
  local failed_groups=0

  for i in "${!db_groups[@]}"; do
    if ! perform_group_backup "${db_groups[$i]}" "${dir_groups[$i]}"; then
      log_error "A failure occurred during the backup of group #$((i+1)). Continuing with the next group."
      failed_groups=$((failed_groups + 1))
    fi
  done
  
  log_info "Backup job finished. Total groups processed: ${total_groups}. Failed groups: ${failed_groups}."
  
  if [ "$failed_groups" -gt 0 ]; then
    log_error "One or more backup groups failed. Please check the logs."
    exit 1
  fi
}

main "$@"