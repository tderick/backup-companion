FROM alpine:3.22

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    unzip \
    postgresql17-client \
    cronie \
    aws-cli \
    zip

# Copy scripts
COPY autobackup.sh /usr/local/bin/autobackup.sh
COPY clean_old_backup.sh /usr/local/bin/clean_old_backup.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY env.sh /usr/local/bin/env.sh

# Make them executable
RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
