#!/bin/bash
set -e

# Source environment
if [ -f /usr/local/bin/env.sh ]; then
  source /usr/local/bin/env.sh
fi

# Ensure log directory exists
mkdir -p /var/log/backup

# Default cron schedule values
CRON_SCHEDULE_BACKUP="${CRON_SCHEDULE_BACKUP:-0 1 * * *}"
CRON_SCHEDULE_CLEAN="${CRON_SCHEDULE_CLEAN:-0 2 * * *}"

# Create cron job file
cat <<EOF > /etc/cron.d/backup_jobs
$CRON_SCHEDULE_BACKUP root /usr/local/bin/autobackup.sh >> /var/log/backup/autobackup.log 2>&1
$CRON_SCHEDULE_CLEAN root /usr/local/bin/clean_old_backup.sh >> /var/log/backup/clean_old_backup.log 2>&1
EOF

# Correct permissions
chmod 0644 /etc/cron.d/backup_jobs

# Capture Environment Variable
{
  # Read binary environ file directly
  while IFS='=' read -r -d '' key value; do
    printf 'export %s="%s"\n' "$key" "$value"
  done < /proc/self/environ
} > /etc/container_environment.sh

# Start crond in foreground
exec crond -f -s
