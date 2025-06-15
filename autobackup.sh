#!/bin/bash
set -euo pipefail

source /etc/container_environment.sh

# Function for logging with timestamp
LOGFILE="/var/log/autobackup.log"
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

# Move to /tmp for backup work
cd /tmp

current_date=$(date +'%d-%m-%Y')
timestamp=$(date -u +'%Y-%m-%dT%H-%M-%SZ')

log "Starting backup for database $DATABASE_NAME at $timestamp"

backup_folder="${DATABASE_NAME}_backup_${timestamp}"

# Create backup folder (with -p to avoid error if exists)
mkdir -p "$backup_folder"

# # Path to filestore
# filestore_dir="/var/lib/odoo/.local/share/Odoo/filestore/$DATABASE_NAME"

# if [ ! -d "$filestore_dir" ]; then
#     log "ERROR: Filestore directory $filestore_dir does not exist!"
#     exit 1
# fi

# # Copy filestore
# cp -r "$filestore_dir" "$backup_folder"

# # Dump database using connection string to avoid duplication
# PG_CONN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${DATABASE_NAME}"
# pg_dump "$PG_CONN" > "${backup_folder}/${DATABASE_NAME}_backup_${current_date}.sql"

# # Zip backup folder
# zip -r "${backup_folder}.zip" "$backup_folder"

# # Remove backup folder after zipping
# rm -rf "$backup_folder"

# # Upload to S3-compatible object storage
# aws --region "$AWS_REGION" --endpoint-url "$AWS_S3_ENDPOINT_URL" s3 cp "${backup_folder}.zip" "s3://${BUCKET_NAME}/${DATABASE_NAME}/${backup_folder}.zip"

# # Remove zip file after upload
# rm -f "${backup_folder}.zip"

log "Backup completed for database $DATABASE_NAME at $(date +'%d-%m-%Y_%Hh-%M')"
