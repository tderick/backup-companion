# Backup Companion

**Backup Companion** is a robust, production-ready Docker container that automates the backup of your databases (**PostgreSQL, MySQL, MariaDB**) and specified directories to any S3-compatible object storage provider.

Built with simplicity and reliability in mind, it uses industry-standard tools like `cron` and `rclone` to create a fire-and-forget backup solution. Simply configure it with environment variables, and it handles the rest—including scheduled backups and automated cleanup of old archives.

## ✨ Features

-   **Multi-Database & Directory Backups**: Dumps your PostgreSQL, MySQL, or MariaDB databases and archives any number of specified directories.
-   **Group-Based Architecture**: Logically group databases and directories to back up multiple, distinct applications from a single container.
-   **S3-Compatible Storage**: Securely uploads backups to any S3 provider, including AWS S3, Cloudflare R2, Minio, DigitalOcean Spaces, and more.
-   **Automated Scheduling**: Uses `cron` to run backups and cleanup jobs on a fully customizable schedule.
-   **Smart Retention Policy**: Automatically deletes old backups from each group based on a configurable number of days.
-   **Production-Ready**: Fails fast on misconfiguration, uses robust `trap`s for cleanup, and provides clear, timestamped logs.

## Core Concept: Backup Groups

The container works by mapping **Backup Groups**. The first group in `DATABASES` is paired with the first group in `DIRECTORIES_TO_BACKUP`.

-   Groups are separated by spaces. If a group itself contains spaces, enclose it in quotes (`""`).
-   To specify that a group has no databases or no directories, use the keyword `NONE`.

#### Group Syntax

-   **`DATABASES`**: Inside a group, database connection strings are separated by **spaces**.
    -   Format: `DB_NAME:DB_HOST:DB_PORT:DB_USER:DB_PASSWORD`
-   **`DIRECTORIES_TO_BACKUP`**: Inside a group, directory paths are separated by **colons (`:`)**.

## Example of usage

### Example 1 with Cloudflare R2

This is an example to automatically back up an Odoo instance to Cloudflare R2.

```yaml
services:
  odoo18:
    # ... odoo service config
  postgres_odoo18:
    image: postgres:17.0
    environment:
      - POSTGRES_DB=my-odoo-db
      - POSTGRES_PASSWORD=odoo
      - POSTGRES_USER=odoo
    # ... odoo db config
  backup-companion:
    image: tderick/backup-companion:1.0-pg17
    environment:
      # --- Core & Scheduling Configuration ---
      - DB_DRIVER=postgres
      - NUMBER_OF_DAYS=30
      - CRON_SCHEDULE_BACKUP="0 3 * * *"
      - CRON_SCHEDULE_CLEAN="0 4 * * *"
      - TZ=UTC

      # --- Backup Group Definition (1 Group) ---
      # DB_NAME:DB_HOST:DB_PORT:DB_USER:DB_PASSWORD
      - DATABASES="my-odoo-db:postgres_odoo18:5432:odoo:odoo"
      # Colon-separated list of directories for this group
      - DIRECTORIES_TO_BACKUP="/var/lib/odoo/filestore:/var/lib/odoo/sessions"

      # --- S3 Storage Configuration ---
      - S3_PROVIDER=cloudflare
      - BUCKET_NAME=odoo-backups
      - AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      - AWS_SECRET_ACCESS_KEY=yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
      - AWS_REGION=auto
      - AWS_S3_ENDPOINT_URL=https://<your_account_id>.r2.cloudflarestorage.com
    volumes:
      # Mount the volumes you want to back up
      - odoo18-web-data:/var/lib/odoo:ro

volumes:
  odoo-db-dataodoo18:
  odoo18-web-data:
```

## ⚙️ Configuration

All configuration is handled via environment variables.

### Required Variables

| Variable | Description | Example |
| :--- | :--- | :--- |
| `DB_DRIVER` | The database driver for all dump operations. | `postgres`, `mysql` |
| `DATABASES` | A space-separated list of database groups. See "Core Concept" section. | `"'db1:...' 'NONE'"` |
| `DIRECTORIES_TO_BACKUP` | A space-separated list of directory groups. See "Core Concept" section. | `"'path1:path2' '/logs'"` |
| `NUMBER_OF_DAYS` | The number of days to retain backups. | `15` |
| `S3_PROVIDER` | The name of your S3 provider. See table below. | `aws` |
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
| `BACKUP_PATH_PREFIX`| An optional prefix (folder path) within the bucket to store backups. | `""` (empty) |
| `DRY_RUN` | If set to `"true"`, the cleanup job will only show what would be deleted. | `false` |
| `RCLONE_FLAGS` | A space-separated string of extra flags for the `rclone copyto` command. | `""` |
| `TZ` | Specify the container's timezone. | `UTC`|

## 🏷️ Docker Image Tags

We provide different image variants for different database client tools. **Use the tag that matches your database server version.**

| Image Tag | PostgreSQL Client | MySQL Client |
| :--- | :--- | :--- |
| `tderick/backup-companion:2.0-pg17-mysql`| 17 | - |
| `tderick/backup-companion:2.0-pg16-mysql`| 16 | - |
| `tderick/backup-companion:2.0-pg15-mysql`| - | - |

## CLI Usage (`docker run`)

While `docker-compose` is recommended, you can also run the container directly.

```shell
docker run -d \
  --name my_app_backup \
  --restart unless-stopped \
  -e DB_DRIVER="postgres" \
  -e NUMBER_OF_DAYS="30" \
  -e DATABASES="my_prod_db:172.17.0.1:5432:user:password" \
  -e DIRECTORIES_TO_BACKUP="/app/public/uploads" \
  -e S3_PROVIDER="aws" \
  -e BUCKET_NAME="my-aws-backup-bucket" \
  -e AWS_ACCESS_KEY_ID="AKIA..." \
  -e AWS_SECRET_ACCESS_KEY="wJalr..." \
  -e AWS_REGION="us-east-1" \
  -v /path/on/host/to/uploads:/app/public/uploads:ro \
  tderick/backup-companion:1.0-pg16
```

Note: Using the host's internal Docker IP (like 172.17.0.1) is brittle. It's better to use Docker networks and service discovery with Docker Compose.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue.

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
