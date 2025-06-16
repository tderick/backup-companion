#!/bin/bash

set -e

# === Required Environment Variables ===

# Fail if not set
: "${DATABASE_NAME:?Environment variable DATABASE_NAME is required}"
: "${BUCKET_NAME:?Environment variable BUCKET_NAME is required}"
: "${AWS_ACCESS_KEY_ID:?Environment variable AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?Environment variable AWS_SECRET_ACCESS_KEY is required}"
: "${POSTGRES_PASSWORD:?Environment variable POSTGRES_PASSWORD is required}"
: "${POSTGRES_USER:?Environment variable POSTGRES_USER is required}"
: "${POSTGRES_HOST:?Environment variable POSTGRES_HOST is required}"
: "${AWS_REGION:?Environment variable AWS_REGION is required}"
: "${AWS_S3_ENDPOINT_URL:?Environment variable AWS_S3_ENDPOINT_URL is required}"
: "${DIRECTORIES_TO_BACKUP:?Environment variable DIRECTORIES_TO_BACKUP is required}"

# === Optional Environment Variables with Defaults ===

# Number of days of data retension
NUMBER_OF_DAYS="${NUMBER_OF_DAYS:-15}"
