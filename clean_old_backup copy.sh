#!/bin/bash 

# Load the environment variables
source /usr/local/bin/env_wrapper.sh

# NUmber of days of data retension
NUMBER_OF_DAYS=15

# Get the current date in the format dd-mm-yyyy
days_ago=$(date -d "$NUMBER_OF_DAYS days ago" +'%d-%m-%Y')

# Set de database name
database_name=$DATABASE_NAME

# Get all the files in the bucket folder
file_list=$(aws --region "$AWS_REGION" --endpoint-url "$AWS_S3_ENDPOINT_URL"  s3 ls "s3://$BUCKET_NAME/$DATABASE_NAME/")

# Extract only the filenames from the file list
filenames=$(echo "$file_list" | awk '{print $NF}')

# Loop through each filename
for filename in $filenames; do
    # Process each filename here
    echo "********Processing file: $filename"
    
    if [[ "$filename" == *"$days_ago"* ]]; then
        echo "******Deleting the file: $filename" >> /var/log/clean_old_backup.log
        aws --region "$AWS_REGION" --endpoint-url "$AWS_S3_ENDPOINT_URL"  s3 rm "s3://$BUCKET_NAME/$database_name/$filename"
    fi
done

