# #!/bin/bash
# #
# # Description:
# #   Called by cron to delete old backups from S3 storage.
# #

# set -euo pipefail

# # --- Logging Functions ---
# log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] [CLEANUP] $*"; }
# log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] [CLEANUP] $*" >&2; }

# # --- Main Logic ---
# main() {
#   log_info "Starting old backup cleanup process..."

#   # === 1. Generate Rclone Config ===
#   local rclone_config_file
#   rclone_config_file=$(mktemp /tmp/rclone_cleanup.XXXXXX)
#   trap 'rm -f "$rclone_config_file"' EXIT

#   declare rclone_provider_value
#   case "${S3_PROVIDER,,}" in
#     aws)                rclone_provider_value="AWS" ;;
#     cloudflare|r2)      rclone_provider_value="Other" ;;
#     minio)              rclone_provider_value="Minio" ;;
#     digitalocean)       rclone_provider_value="DigitalOcean" ;;
#     *)                  rclone_provider_value="Other" ;;
#   esac

#   cat <<EOF > "$rclone_config_file"
# [s3_remote]
# type = s3
# provider = ${rclone_provider_value}
# access_key_id = ${AWS_ACCESS_KEY_ID}
# secret_access_key = ${AWS_SECRET_ACCESS_KEY}
# region = ${AWS_REGION}
# endpoint = ${AWS_S3_ENDPOINT_URL:-}
# acl = private
# EOF

#   # === 2. Format Target Path and Execute Cleanup ===
#   # This logic mirrors the path creation in autobackup.sh to ensure
#   # we are deleting from the exact same directory where backups are stored.
#   local path_components=()
#   if [[ -n "${BACKUP_PATH_PREFIX:-}" ]]; then
#       path_components+=("$(echo "${BACKUP_PATH_PREFIX}" | sed 's:^/*::;s:/*$::')")
#   fi
#   path_components+=("${DATABASE_NAME}")
  
#   local remote_folder_path
#   remote_folder_path=$(IFS=/; echo "${path_components[*]}")

#   # The final path to the directory that needs cleaning.
#   local remote_path_to_clean="s3_remote:${BUCKET_NAME}/${remote_folder_path}/"
#   log_info "Deleting files older than ${NUMBER_OF_DAYS} days from '${remote_path_to_clean}'..."

#   # The 'rclone delete' command with --min-age is perfect for this.
#   if ! rclone --config "$rclone_config_file" delete "$remote_path_to_clean" --min-age "${NUMBER_OF_DAYS}d"; then
#     log_error "Rclone cleanup command failed. Please check logs."
#     exit 1
#   fi

#   log_info "Cleanup process completed successfully."
# }

# main "$@"