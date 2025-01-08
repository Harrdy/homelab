#!/bin/bash

source_folders=("root@192.168.171.1:/mnt/user/appdata" "root@192.168.171.2:/mnt/user/appdata" "/mnt/user/appdata")

ssh_key="/root/.ssh/id_rsa4096"
base_backup_folder="/mnt/user/backup/appdata"


backup_datetime=$(date +"%Y%m%d_%H%M%S")
temp_dir="/mnt/nvme_pool/backup_temp"
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"

TARGET_IPS=()
for entry in "${source_folders[@]}"; do
    if [[ $entry =~ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
        TARGET_IPS+=("${BASH_REMATCH[1]}")
    fi
done

for TARGET_IP in "${TARGET_IPS[@]}"; do
    if sed -i "/$TARGET_IP/d" "$KNOWN_HOSTS_FILE"; then
        echo "Fingerprint für $TARGET_IP wurde erfolgreich entfernt."
    else
        echo "Es gab ein Problem beim Entfernen des Fingerprints für $TARGET_IP."
    fi
done

process_source_folder() {
    local source_folder="$1"
    local effective_source="$source_folder"
    local server_name

    if [[ "$source_folder" == *@*:* ]]; then
        server_name=$(echo "$source_folder" | cut -d@ -f2 | cut -d: -f1)
    else
        server_name="local"
    fi

    backup_folder="$base_backup_folder/$server_name"
    mkdir -p "$backup_folder"

    if [[ "$source_folder" == *@*:* ]]; then
        echo "Remote-Quelle erkannt: $source_folder"
        mkdir -p "$temp_dir"

        echo "Synchronisiere Daten von $source_folder nach $temp_dir"
        rsync -e "ssh -i $ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=$KNOWN_HOSTS_FILE" -avz --rsync-path="sudo rsync" "$source_folder/" "$temp_dir/"

        effective_source="$temp_dir"
    fi

    for subfolder in "$effective_source"/*; do
        if [ -d "$subfolder" ]; then
            subfolder_name=$(basename "$subfolder")
            target_folder="$backup_folder/$subfolder_name"
            target_file="$subfolder_name-$backup_datetime.tar.gz"
            target="$target_folder/$target_file"

            if [ ! -d "$target_folder" ]; then
                mkdir -p "$target_folder"
            fi

            echo "Packe und komprimiere $subfolder_name nach $target"
            tar --exclude='*/Media' --exclude='*/jellyfin/cache' --exclude='*/jellyfin/config/metadata' --exclude='photoprism/cache' --exclude='photoprism/sidecar' -czf "$target" -C "$effective_source" "$subfolder_name"
        fi
    done

    if [[ "$source_folder" == *@*:* ]]; then
        echo "Lösche temporäre Dateien aus $temp_dir"
        rm -rf "$temp_dir"
    fi
}

for source_folder in "${source_folders[@]}"; do
    process_source_folder "$source_folder"
done

# Lösche Backups, die älter als 7 Tage sind, in allen Backup-Ordnern
find "$base_backup_folder" -type f -name "*.tar.gz" -mtime +7 -exec rm {} \;
find "$base_backup_folder/local/photoprism" -type f -name "*.tar.gz" -mtime +2 -exec rm {} \;
find "$base_backup_folder/local/mediastack1" -type f -name "*.tar.gz" -mtime +2 -exec rm {} \;

echo "Backup abgeschlossen."
