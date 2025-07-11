#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Environment Validator
# ==============================================================================
#
# Description:
#   This script validates all required environment variables when the container
#   starts. Its primary purpose is to act as the first line of defense against
#   misconfiguration, failing fast with clear error messages.
#
# --- CONFIGURATION: BACKUP GROUPS (MANDATORY) ---
#
# The script validates "backup groups". A group is a collection of databases
# and/or directories that are backed up together into a single archive.
#
# The number of space-separated groups in DATABASES and DIRECTORIES_TO_BACKUP
# MUST be identical.
#
# - DATABASES: Space-separated groups of database connection strings.
#   - A group of DBs is a space-separated list of connection strings.
#   - Use "NONE" (case-sensitive) for groups without databases.
#   - Format: "'db1:h1:p1:u1:p1 db2:h2:p2:u2:p2' 'db3:h3:p3:u3:p3' 'NONE'"
#
# - DIRECTORIES_TO_BACKUP: Space-separated groups of directory paths.
#   - A group of directories is a colon-separated (:) list of paths.
#   - Use "NONE" (case-sensitive) for groups without directories.
#   - Format: "'/var/www/app1:/etc/app1' 'NONE' '/var/log/app3'"
#
# NOTE: At least one of the corresponding groups must not be "NONE".
#       A group of "'NONE' 'NONE'" is invalid.
#
# --- Configuration: S3 Provider ---
#   (Validation for S3 settings remains the same)
#
# ==============================================================================

set -euo pipefail

# === Core Service Validation ===
: "${CRON_SCHEDULE_BACKUP:?CRON_SCHEDULE_BACKUP is required}"
: "${CRON_SCHEDULE_CLEAN:?CRON_SCHEDULE_CLEAN is required}"
: "${DB_DRIVER:?DB_DRIVER is required (e.g., 'postgres', 'mysql').}"

case "${DB_DRIVER,,}" in
  postgres|mysql|mariadb)
    echo "--- [env.sh] Using DB_DRIVER: ${DB_DRIVER}"
    ;;
  *)
    echo "Error: Unknown DB_DRIVER: '${DB_DRIVER}'. Must be 'postgres', 'mysql', or 'mariadb'." >&2
    exit 1
    ;;
esac

# === Backup Group Configuration Validation ===
echo "--- [env.sh] Validating Backup Group Configuration ---"
: "${DATABASES:?DATABASES environment variable is required.}"
: "${DIRECTORIES_TO_BACKUP:?DIRECTORIES_TO_BACKUP environment variable is required.}"

# Read space-separated groups into arrays. This is the standard, safe way.
read -r -a db_groups <<< "$DATABASES"
read -r -a dir_groups <<< "$DIRECTORIES_TO_BACKUP"

# 1. Validate that group counts match.
if [ ${#db_groups[@]} -ne ${#dir_groups[@]} ]; then
  echo "Error: Configuration mismatch." >&2
  echo "The number of groups in DATABASES (${#db_groups[@]}) does not match the number of groups in DIRECTORIES_TO_BACKUP (${#dir_groups[@]})." >&2
  exit 1
fi
echo "Found ${#db_groups[@]} backup group(s). Proceeding with validation..."

# 2. Loop through each group to validate its contents.
for i in "${!db_groups[@]}"; do
  group_num=$((i + 1))
  db_group="${db_groups[$i]}"
  dir_group="${dir_groups[$i]}"

  echo "  - Validating Group #${group_num}..."

  # A group cannot be completely empty.
  if [[ "$db_group" == "NONE" && "$dir_group" == "NONE" ]]; then
    echo "Error: Group #${group_num} is empty. Both DATABASES and DIRECTORIES_TO_BACKUP are 'NONE'." >&2
    exit 1
  fi

  # Validate the database part of the group
  if [[ "$db_group" != "NONE" ]]; then
    for db_conn_string in $db_group; do
      # Use `tr` to count colons. A valid string must have 4 colons (5 parts).
      if [[ $(tr -dc ':' <<< "$db_conn_string" | awk '{ print length }') -ne 4 ]]; then
        echo "Error: Invalid database connection string format in Group #${group_num}." >&2
        echo "Malformed entry: '${db_conn_string}'" >&2
        echo "Expected format: 'DB_NAME:DB_HOST:DB_PORT:DB_USER:DB_PASSWORD'" >&2
        exit 1
      fi
      # We don't need to check for empty parts here, as the backup script will fail if they are missing.
      # The main goal is to validate the structure.
    done
  fi
  
  # Validate the directory part of the group
  if [[ "$dir_group" != "NONE" ]]; then
    if [[ "$dir_group" == *'::'* ]] || [[ "${dir_group:0:1}" == ":" ]] || [[ "${dir_group: -1}" == ":" ]]; then
      echo "Error: Invalid directory format in Group #${group_num}." >&2
      echo "Malformed entry: '${dir_group}'" >&2
      echo "Details: Found empty path component (e.g., '/path/one::/path/two' or leading/trailing colons)." >&2
      exit 1
    fi
  fi
done
echo "--- [env.sh] All backup groups are correctly configured. ---"


# === S3 Provider Validation (Unchanged) ===
echo "--- [env.sh] Validating S3 Provider Environment Variables ---"
: "${S3_PROVIDER:?S3_PROVIDER is required (e.g., 'aws', 'cloudflare', 'minio')}"
: "${BUCKET_NAME:?BUCKET_NAME is required for S3 storage}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required for S3 storage}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required for S3 storage}"

case "${S3_PROVIDER,,}" in
  aws)
    : "${AWS_REGION:?AWS_REGION is required for S3_PROVIDER 'aws'}"
    if [ -n "${AWS_S3_ENDPOINT_URL:-}" ]; then
        echo "Warning: AWS_S3_ENDPOINT_URL is set for S3_PROVIDER 'aws' but should be empty. It will be ignored." >&2
    fi
    ;;
  cloudflare|r2)
    : "${AWS_S3_ENDPOINT_URL:?AWS_S3_ENDPOINT_URL is required for S3_PROVIDER '${S3_PROVIDER}'}"
    export AWS_REGION="${AWS_REGION:-auto}"
    ;;
  *) # minio, digitalocean, wasabi, etc.
    : "${AWS_REGION:?AWS_REGION is required for S3_PROVIDER '${S3_PROVIDER}'}"
    : "${AWS_S3_ENDPOINT_URL:?AWS_S3_ENDPOINT_URL is required for S3_PROVIDER '${S3_PROVIDER}'}"
    ;;
esac

echo "--- [env.sh] All required S3 variables for provider '${S3_PROVIDER}' are present. ---"