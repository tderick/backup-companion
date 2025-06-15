#!/bin/bash
set -e

# Source environment
if [ -f /usr/local/bin/env.sh ]; then
  source /usr/local/bin/env.sh
fi

# Default schedules
CRON_SCHEDULE_BACKUP="${CRON_SCHEDULE_BACKUP:-0 1 * * *}"
CRON_SCHEDULE_CLEAN="${CRON_SCHEDULE_CLEAN:-0 2 * * *}"

# Ensure log files exist and are writable
mkdir -p /var/log/backup
touch /var/log/backup/autobackup.log /var/log/backup/clean_old_backup.log

# Write crontab (no `root` user field needed since non-root user will run crond)
cat <<EOF > /home/backup/cronjobs
$CRON_SCHEDULE_BACKUP /bin/bash /usr/local/bin/autobackup.sh >> /var/log/backup/autobackup.log 2>&1
$CRON_SCHEDULE_CLEAN /bin/bash /usr/local/bin/clean_old_backup.sh >> /var/log/backup/clean_old_backup.log 2>&1
EOF

# Install crontab
crontab /home/backup/cronjobs

# Run cron in foreground
# exec crond -n -s
# Run cron in foreground, with the PID file in a writable location
exec crond -f -P /home/backup/crond.pid