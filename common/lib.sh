#!/bin/bash
#
# ==============================================================================
# S3 Backup Container - Shared Library
# ==============================================================================
#
# Description:
#   This script contains shared utility functions that can be sourced by other
#   scripts in this project to promote code reuse (DRY principle).
#
# ==============================================================================

# Note: set -euo pipefail should be set in the scripts that *source* this library.

# --- Logging Functions ---
# Provides standardized log output with timestamps.
log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] [$SCRIPT_NAME] $*"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] [$SCRIPT_NAME] $*" >&2; }


# --- Rclone Configuration Function ---

#
# Generates an rclone configuration file at the specified path.
# This centralizes the logic for translating S3_PROVIDER to rclone's provider type.
#
# @param $1 - The path to the output config file.
#
generate_rclone_config() {
  if [ -z "$1" ]; then
    log_error "generate_rclone_config requires the output file path as an argument."
    return 1
  fi

  local config_path="$1"
  local rclone_provider_value

  case "${S3_PROVIDER,,}" in
    aws)          rclone_provider_value="AWS" ;;
    cloudflare|r2)rclone_provider_value="Other" ;;
    minio)        rclone_provider_value="Minio" ;;
    digitalocean) rclone_provider_value="DigitalOcean" ;;
    *)            rclone_provider_value="Other" ;;
  esac

  cat <<EOF > "$config_path"
[s3_remote]
type = s3
provider = ${rclone_provider_value}
access_key_id = ${AWS_ACCESS_KEY_ID}
secret_access_key = ${AWS_SECRET_ACCESS_KEY}
region = ${AWS_REGION}
endpoint = ${AWS_S3_ENDPOINT_URL:-}
acl = private
EOF
}

# --- Shared Cleanup and Trap Handler ---

#
# Generic cleanup function designed to be called by a trap.
# It cleans up the temporary rclone config file.
#
# CONTRACT: This function REQUIRES the following global variables to be set
#           in the calling script:
#           - RCLONE_CONFIG_FILE: Path to the temporary rclone config.
#           - SCRIPT_NAME: The name of the script for logging purposes.
#
_cleanup_and_exit() {
  local exit_code=$?
  set +e # Don't exit on error during cleanup

  if [ -f "$RCLONE_CONFIG_FILE" ]; then
    log_info "Removing temporary rclone config file..."
    rm -f "$RCLONE_CONFIG_FILE"
  fi

  log_info "${SCRIPT_NAME} script finished with exit code ${exit_code}."
  exit $exit_code
}

#
# Sets the standard exit trap for scripts that create a temporary rclone config.
# Calling this function once is all that's needed.
#
setup_exit_trap() {
  trap _cleanup_and_exit EXIT
}