```shell
docker build --no-cache -f backups/mysql/Dockerfile.mysql -t tderick/backup-companion:1.1-mysql .
```

```shell
 docker build --no-cache -f backups/pg/Dockerfile.pg15 -t tderick/backup-companion:1.0-pg15 .
```