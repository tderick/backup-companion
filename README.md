# Backup Companion

**Backup Companion** is a robust, production-ready Docker container that automates the backup of your PostgreSQL databases and specified directories to any S3-compatible object storage provider.

Built with simplicity and reliability in mind, it uses industry-standard tools like `cron`, `rclone`, and `pg_dump` to create a fire-and-forget backup solution. Simply configure it with environment variables, and it handles the rest—including scheduled backups and automated cleanup of old archives.

## ✨ Features

- **PostgreSQL & Directory Backups**: Dumps your PostgreSQL database and archives any number of specified directories into a single `.tar.gz` file.
- **S3-Compatible Storage**: Securely uploads backups to any S3 provider, including AWS S3, Cloudflare R2, Minio, DigitalOcean Spaces, and more.
- **Automated Scheduling**: Uses `cron` to run backups and cleanup jobs on a fully customizable schedule.
- **Smart Retention Policy**: Automatically deletes old backups based on a configurable number of days to keep.
- **Production-Ready**: Fails fast on misconfiguration, uses robust `trap`s for cleanup, and provides clear, timestamped logs.


## Example of usage

### Example 1 with Cloudflare R2

This is an example to automatically backup an odoo instance to Cloudflare R2

```yaml
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
        - POSTGRES_PASSWORD=odoo
        - POSTGRES_USER=odoo
        - PGDATA=/var/lib/postgresql/data/pgdata
      volumes:
        - odoo-db-dataodoo18:/var/lib/postgresql/data/pgdata
    cron:
      image: tderick/backup-companion:1.0-pg17
      environment:
        # --- Target Database Configuration ---
        - DATABASE_NAME=my-odoo-db
        - POSTGRES_PASSWORD=odoo
        - POSTGRES_USER=odoo
        # Use the service name from your docker-compose file as the host
        - POSTGRES_HOST=postgres_odoo18
        # --- S3 Storage Configuration ---
        # See the "S3 Provider Configuration" section below for more examples
        - S3_PROVIDER=cloudflare
        - BUCKET_NAME=odoo-backups
        - AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        - AWS_SECRET_ACCESS_KEY=yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
        - AWS_REGION=auto
        - AWS_S3_ENDPOINT_URL=https://[<your_account_id>].eu.r2.cloudflarestorage.com
        # A space-separated list of absolute paths inside the container to back up.
        # These paths must be mounted via volumes.
        - DIRECTORIES_TO_BACKUP=/var/lib/odoo/.local/share/Odoo/filestore/my-odoo-db /var/lib/odoo/.local/share/Odoo/sessions
        # --- Scheduling and Retention (Optional) ---
        # Run backup at 3:00 AM daily (server time)
        - CRON_SCHEDULE_BACKUP="0 3 * * *"
        # Run cleanup at 4:00 AM daily
        - CRON_SCHEDULE_CLEAN="0 4 * * *"
        # Keep backups for 30 days
        - NUMBER_OF_DAYS=30
      volumes:
        - odoo18-web-data:/var/lib/odoo

  volumes:
    odoo-db-dataodoo18:
    odoo18-web-data:
```
``

## ⚙️ Configuration

All configuration is handled via environment variables.

### Required Variables

| Variable | Description | Example |
| :--- | :--- | :--- |
| `DATABASE_NAME` | The name of the PostgreSQL database to dump. | `my_app_db` |
| `POSTGRES_USER` | The username for the PostgreSQL database. | `backup_user` |
| `POSTGRES_PASSWORD`| The password for the PostgreSQL user. | `s3cr3t_p4ssw0rd` |
| `POSTGRES_HOST` | The hostname or IP address of the PostgreSQL server. | `postgres_db_host` |
| `DIRECTORIES_TO_BACKUP` | A space-separated string of absolute paths inside the container to archive. | `"/var/www/uploads /etc/my_app"` |
| `S3_PROVIDER` | The name of your S3 provider. See the table below for supported values. | `aws` |
| `BUCKET_NAME` | The name of the S3 bucket to store backups in. | `my-company-backups` |
| `AWS_ACCESS_KEY_ID` | Your S3 Access Key ID. | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY`| Your S3 Secret Access Key. | `wJalrXUtnFEMI/K7MDENG...` |

### S3 Provider Configuration

Set `S3_PROVIDER` to one of the following (case-insensitive) values and provide the corresponding `AWS_REGION` and `AWS_S3_ENDPOINT_URL`.

| `S3_PROVIDER` Value(s) | Service Name | `AWS_REGION` | `AWS_S3_ENDPOINT_URL` |
| :--- | :--- | :--- | :--- |
| **`aws`** | Amazon Web Services S3 | **Required** | Must be **unset/empty** |
| **`cloudflare`** or **`r2`** | Cloudflare R2 | Optional (defaults to `auto`) | **Required** |
| **`minio`** | Minio (Self-hosted) | **Required** | **Required** |
| **`digitalocean`** | DigitalOcean Spaces | **Required** | **Required** |
| *any other name* | Backblaze, Wasabi, etc. | **Required** | **Required** |

### Optional Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `CRON_SCHEDULE_BACKUP` | The cron schedule for running the backup job. | `"0 1 * * *"` (1:00 AM daily) |
| `CRON_SCHEDULE_CLEAN` | The cron schedule for running the cleanup job. | `"0 2 * * *"` (2:00 AM daily) |
| `NUMBER_OF_DAYS` | The number of days to retain backups for. Older backups will be deleted. | `15` |
| `BACKUP_PATH_PREFIX`| An optional prefix (folder path) within the bucket to store backups. | `""` (empty) |
| `AWS_S3_ENDPOINT_URL`| The endpoint URL for non-AWS S3 providers. | `""` (empty) |
| `DRY_RUN` | If set to `"true"`, the cleanup job will only show what would be deleted. | `false` |
| `RCLONE_FLAGS` | A space-separated string of extra flags for the `rclone copyto` command. | `""` |
| `TZ` | Specify the timezone | `UTC`|

## 🏷️ Docker Image Tags

We provide different image variants for different versions of PostgreSQL client tools. Always use the tag that matches your database version.

*   `your-dockerhub-username/backup-companion:latest`: Points to the latest stable PostgreSQL version (recommended for most users).
*   `tderick/backup-companion:1.0-pg17`: Rolling tag for the latest release supporting PostgreSQL 17.
*   `tderick/backup-companion:1.0-pg16`: Rolling tag for the latest release supporting PostgreSQL 16.
*   `tderick/backup-companion:1.0-pg16`: Rolling tag for the latest release supporting PostgreSQL 15.

## CLI Usage (`docker run`)

While `docker-compose` is recommended, you can also run the container directly.

```bash
docker run -d \
  --name my_app_backup \
  --restart unless-stopped \
  -e DATABASE_NAME="my_production_db" \
  -e POSTGRES_USER="my_db_user" \
  -e POSTGRES_PASSWORD="a_very_secure_password" \
  -e POSTGRES_HOST="172.17.0.1" \
  -e S3_PROVIDER="aws" \
  -e BUCKET_NAME="my-aws-backup-bucket" \
  -e AWS_ACCESS_KEY_ID="AKIA..." \
  -e AWS_SECRET_ACCESS_KEY="wJalr..." \
  -e AWS_REGION="us-east-1" \
  -e DIRECTORIES_TO_BACKUP="/app/public/uploads" \
  -e NUMBER_OF_DAYS="30" \
  -v /path/on/host/to/uploads:/app/public/uploads:ro \
    tderick/backup-companion:1.0-pg16
```
_Note: Using the host's internal Docker IP (like `172.17.0.1`) for `POSTGRES_HOST` can be brittle. It's better to use Docker networks and service discovery with Docker Compose._

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue.

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
