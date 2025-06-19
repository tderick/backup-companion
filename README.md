🛡️ Backup Companion

Backup Companion is a production-ready Docker container that automatically backs up your PostgreSQL databases and directory paths to any S3-compatible object storage.

Simple to configure. Reliable in production. Designed to be fire-and-forget using cron, pg_dump, and rclone.
✨ Features

    📦 PostgreSQL & Directory Backups
    Dumps your database and archives directories into a single .tar.gz file.

    ☁️ S3-Compatible Uploads
    Supports AWS S3, Cloudflare R2, MinIO, DigitalOcean Spaces, and more.

    ⏰ Automated Scheduling
    Backup and cleanup via fully configurable cron jobs.

    🧹 Retention Policy
    Deletes old backups after a configurable number of days.

    🛠️ Robust by Design
    Fails fast on config errors, uses trap for cleanup, logs with timestamps.

🚀 Example Usage (Docker Compose)

Backup your Odoo instance to Cloudflare R2:

services:
  odoo18:
    image: odoo:18.0
    volumes:
      - ./etc/odoo:/etc/odoo
      - odoo18-web-data:/var/lib/odoo
    ports:
      - 8069:8069
    depends_on:
      - postgres_odoo18

  postgres_odoo18:
    image: postgres:17.0
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - odoo-db-dataodoo18:/var/lib/postgresql/data/pgdata

  cron:
    image: tderick/backup-companion:1.0-pg17
    environment:
      - DATABASE_NAME=my-odoo-db
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
      - POSTGRES_HOST=postgres_odoo18
      - S3_PROVIDER=cloudflare
      - BUCKET_NAME=odoo-backups
      - AWS_ACCESS_KEY_ID=xxxxxxxx
      - AWS_SECRET_ACCESS_KEY=yyyyyyyy
      - AWS_REGION=auto
      - AWS_S3_ENDPOINT_URL=https://<your_account>.r2.cloudflarestorage.com
      - DIRECTORIES_TO_BACKUP=/var/lib/odoo/.local/share/Odoo/filestore/my-odoo-db /var/lib/odoo/.local/share/Odoo/sessions
      - CRON_SCHEDULE_BACKUP=0 3 * * *
      - CRON_SCHEDULE_CLEAN=0 4 * * *
      - NUMBER_OF_DAYS=30
    volumes:
      - odoo18-web-data:/var/lib/odoo

volumes:
  odoo-db-dataodoo18:
  odoo18-web-data:

⚙️ Configuration (ENV Variables)
Variable	Required	Description
DATABASE_NAME	✅	PostgreSQL database name to back up
POSTGRES_USER	✅	PostgreSQL username
POSTGRES_PASSWORD	✅	PostgreSQL password
POSTGRES_HOST	✅	Hostname/IP of the PostgreSQL server
DIRECTORIES_TO_BACKUP	✅	Space-separated list of absolute paths to archive
S3_PROVIDER	✅	One of: aws, cloudflare, r2, minio, digitalocean, etc.
BUCKET_NAME	✅	Name of your target bucket
AWS_ACCESS_KEY_ID	✅	Your S3 access key
AWS_SECRET_ACCESS_KEY	✅	Your S3 secret key
Optional
Variable	Default	Description
AWS_REGION	us-east-1	Required for AWS and most providers
AWS_S3_ENDPOINT_URL	(empty)	Required for R2, MinIO, etc.
BACKUP_PATH_PREFIX	(empty)	Prefix path within bucket
CRON_SCHEDULE_BACKUP	0 1 * * *	Cron schedule for backups
CRON_SCHEDULE_CLEAN	0 2 * * *	Cron schedule for cleanup
NUMBER_OF_DAYS	15	Retention duration (in days)
DRY_RUN	false	If "true", cleanup only logs deletions
RCLONE_FLAGS	(empty)	Extra flags passed to rclone copyto
🧭 S3 Provider Matrix
Provider	S3_PROVIDER	AWS_REGION	AWS_S3_ENDPOINT_URL
AWS S3	aws	✅	❌
Cloudflare R2	cloudflare, r2	Optional	✅
MinIO	minio	✅	✅
DigitalOcean Spaces	digitalocean	✅	✅
Other (Wasabi, etc.)	custom name	✅	✅
🐳 CLI Usage (docker run)

docker run -d \
  --name my_app_backup \
  --restart unless-stopped \
  -e DATABASE_NAME="my_db" \
  -e POSTGRES_USER="user" \
  -e POSTGRES_PASSWORD="pass" \
  -e POSTGRES_HOST="172.17.0.1" \
  -e S3_PROVIDER="aws" \
  -e BUCKET_NAME="backups" \
  -e AWS_ACCESS_KEY_ID="AKIA..." \
  -e AWS_SECRET_ACCESS_KEY="wJalr..." \
  -e AWS_REGION="us-east-1" \
  -e DIRECTORIES_TO_BACKUP="/app/uploads" \
  -e NUMBER_OF_DAYS="30" \
  -v /host/uploads:/app/uploads:ro \
  tderick/backup-companion:1.0-pg17

🏷️ Available Tags

Use the tag that matches your PostgreSQL version:

    tderick/backup-companion:latest – latest stable release

    tderick/backup-companion:1.0-pg17 – for PostgreSQL 17

    tderick/backup-companion:1.0-pg16 – for PostgreSQL 16

    tderick/backup-companion:1.0-pg15 – for PostgreSQL 15

🤝 Contributing

Found a bug? Have a feature request? Open an issue or submit a pull request — contributions welcome!
📜 License

This project is licensed under the MIT License.