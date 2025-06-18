#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Environment Validator
# ==============================================================================
#
# Description:
#   This script validates all required environment variables when the container
#   starts. It is sourced by the main `entrypoint.sh` script.
#
#   Its primary purpose is to act as the first line of defense against
#   misconfiguration, failing fast with a clear error message if a required
#   variable is missing or if the combination of variables is incorrect for the
#   chosen `S3_PROVIDER`.
#
# --- Configuration: S3_PROVIDER ---
#
# The `S3_PROVIDER` environment variable is the most important setting. This script
# validates that the correct corresponding variables (`AWS_REGION` and
# `AWS_S3_ENDPOINT_URL`) are also set. Use one of the following exact values
# (case-insensitive):
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

set -e

echo "--- [env.sh] Validating S3 Provider Environment Variables ---"

# === Required for ANY Backup Task ===
: "${DATABASE_NAME:?Environment variable DATABASE_NAME is required}"
: "${POSTGRES_USER:?Environment variable POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?Environment variable POSTGRES_PASSWORD is required}"
: "${POSTGRES_HOST:?Environment variable POSTGRES_HOST is required}"
: "${DIRECTORIES_TO_BACKUP:?Environment variable DIRECTORIES_TO_BACKUP is required}"

# === Required for ANY S3-Compatible Provider ===
: "${S3_PROVIDER:?S3_PROVIDER is required (e.g., 'aws', 'cloudflare', 'minio', 'digitalocean')}"
: "${BUCKET_NAME:?BUCKET_NAME is required for S3 storage}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required for S3 storage}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required for S3 storage}"

# === Provider-Specific Validation ===
# Ensure the right combination of region/endpoint is provided for the chosen S3 provider.
case "${S3_PROVIDER,,}" in # Convert to lowercase for case-insensitivity
  aws)
    # AWS S3 requires a region but does not use a custom endpoint URL.
    : "${AWS_REGION:?AWS_REGION is required for S3_PROVIDER 'aws'}"
    ;;
  cloudflare|r2)
    # Cloudflare R2 requires an endpoint URL. Region is not used but can be set to 'auto'.
    : "${AWS_S3_ENDPOINT_URL:?AWS_S3_ENDPOINT_URL is required for S3_PROVIDER '${S3_PROVIDER}'}"
    export AWS_REGION="${AWS_REGION:-auto}" # Set a safe default if not provided
    ;;
  minio|digitalocean|*)
    # Most other providers (Minio, DigitalOcean, etc.) require both.
    : "${AWS_REGION:?AWS_REGION is required for S3_PROVIDER '${S3_PROVIDER}'}"
    : "${AWS_S3_ENDPOINT_URL:?AWS_S3_ENDPOINT_URL is required for S3_PROVIDER '${S3_PROVIDER}'}"
    ;;
esac

# === Optional with Defaults ===
export NUMBER_OF_DAYS="${NUMBER_OF_DAYS:-30}"
# Optional path prefix within the bucket
export BACKUP_PATH_PREFIX="${BACKUP_PATH_PREFIX:-}"

echo "--- [env.sh] All required S3 variables for provider '${S3_PROVIDER}' are present. ---"