#!/bin/bash 

# Load the environment variables
source /usr/local/bin/env_wrapper.sh

# Change the directory to /tmp
cd /tmp

# Get the current date in the format dd-mm-yyyy
current_date=$(date +'%d-%m-%Y')

echo "Starting backup the database $DATABASE_NAME : $(date +'%d-%m-%Y_%Hh-%M')" >> /var/log/autobackup.log
     
# The filestore path
dir="/var/lib/odoo/.local/share/Odoo/filestore/$DATABASE_NAME"

# Set de database name
database_name=$DATABASE_NAME

# Backup folder name
folder_name="${database_name}_backup_$current_date"

# Create the backup folder
mkdir "$folder_name"

# Copy the filestore folder to the backup folder
cp -r "$dir" "$folder_name"

# Dump the odoo database to the backup folder
pg_dump -d "$database_name" > "$folder_name/${database_name}_backup_$current_date.sql"

pg_dump postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:5432/$database_name > "$folder_name/${database_name}_backup_$current_date.sql"

# Zip the backup folder
zip -r "$folder_name.zip" "$folder_name"   

# Delete the backup folder
rm -R "$folder_name"

# Updload the backup to the contabo object storage inside a specifique folder
aws --region "$AWS_REGION" --endpoint-url "$AWS_S3_ENDPOINT_URL"  s3 cp "$folder_name.zip" "s3://$BUCKET_NAME/$database_name/$folder_name.zip"

# Delete the backup zip file
rm "$folder_name.zip"

echo "Finished backup the database $DATABASE_NAME: $(date +'%d-%m-%Y_%Hh-%M')" >> /var/log/autobackup.log
