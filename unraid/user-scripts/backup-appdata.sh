#!/bin/bash

source_folder="/mnt/user/appdata"
backup_folder="/mnt/user/backup/docker"
backup_datetime=$(date +"%Y%m%d_%H%M%S")

for subfolder in "$source_folder"/*; do
    if [ -d "$subfolder" ]; then
        subfolder_name=$(basename "$subfolder")
        target_folder="$backup_folder/$subfolder_name"
        target_file="$subfolder_name-$backup_datetime.tar.gz"
        target="$target_folder/$target_file"

        if [ ! -d "$target_folder" ]; then
            mkdir -p "$target_folder"
        fi

        echo "Packe und komprimiere $subfolder_name nach $target"
        tar --exclude='*/Media' --exclude='*/jellyfin/cache' --exclude='*/jellyfin/config/metadata' --exclude='*/photoprism/cache' -czf "$target" -C "$source_folder" "$subfolder_name"
    fi
done

find "$backup_folder" -type f -name "*.tar.gz" -mtime +7 -exec rm {} \;

find "/mnt/user/backup/docker/photoprism" -type f -name "*.tar.gz" -mtime +2 -exec rm {} \;
find "/mnt/user/backup/docker/mediastack1" -type f -name "*.tar.gz" -mtime +2 -exec rm {} \;

echo "Backup abgeschlossen."