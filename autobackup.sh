#!/bin/bash
set -euo pipefail

# === Load environment variables ===
[ -f /etc/container_environment.sh ] && source /etc/container_environment.sh

# === Log file setup ===
LOGFILE="/var/log/autobackup.log"
mkdir -p "$(dirname "$LOGFILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

# === Prepare backup folder ===
cd /tmp
current_date=$(date +'%d-%m-%Y')
timestamp=$(date -u +'%Y-%m-%dT%H-%M-%SZ')
backup_folder="${DATABASE_NAME}_backup_${timestamp}"

log "Starting backup for database '${DATABASE_NAME}' at ${timestamp}"
mkdir -p "$backup_folder"

# === Backup specified directories ===
for dir_path in $DIRECTORIES_TO_BACKUP; do
    if [ -d "$dir_path" ]; then
        log "Backing up directory: $dir_path"
        cp -a "$dir_path" "$backup_folder/"
    else
        log "Skipping missing directory: $dir_path"
    fi
done

# === Dump PostgreSQL database ===
export PGPASSWORD="$POSTGRES_PASSWORD"
pg_dump -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$DATABASE_NAME" \
    > "${backup_folder}/${DATABASE_NAME}_backup_${timestamp}.sql"

# PG_CONN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${DATABASE_NAME}"
# pg_dump "$PG_CONN" > "${backup_folder}/${DATABASE_NAME}_backup_${current_date}.sql"
log "Database dump completed"

# === Archive backup ===
zip -rq "${backup_folder}.zip" "$backup_folder"
log "Zipped backup to ${backup_folder}.zip"

# === Upload to object storage ===
# aws --region "$AWS_REGION" \
#     --endpoint-url "$AWS_S3_ENDPOINT_URL" \
#     s3 cp "${backup_folder}.zip" "s3://${BUCKET_NAME}/${DATABASE_NAME}/${backup_folder}.zip"

# log "Uploaded backup to S3: ${BUCKET_NAME}/${DATABASE_NAME}/${backup_folder}.zip"

# # === Cleanup ===
# rm -rf "$backup_folder" "${backup_folder}.zip"
# log "Cleaned up temporary files"

# log "Backup completed for database '${DATABASE_NAME}' at $(date +'%Y-%m-%d %H:%M:%S')"
