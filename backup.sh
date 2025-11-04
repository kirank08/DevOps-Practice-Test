#!/bin/bash

CONFIG_FILE="./backup.config"
LOG_FILE="./backup.log"
LOCK_FILE="/tmp/backup.lock"

# === Load configuration ===
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    BACKUP_DESTINATION="$HOME/backups"
    EXCLUDE_PATTERNS=".git,node_modules,.cache"
    DAILY_KEEP=7
    WEEKLY_KEEP=4
    MONTHLY_KEEP=3
fi

mkdir -p "$BACKUP_DESTINATION"

# === Logging function ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# === Prevent multiple runs ===
if [ -f "$LOCK_FILE" ]; then
    log "ERROR: Script is already running (lock file exists)"
    exit 1
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

# === Create backup ===
create_backup() {
    local SOURCE_DIR=$1
    if [ ! -d "$SOURCE_DIR" ]; then
        log "ERROR: Source folder not found: $SOURCE_DIR"
        exit 1
    fi

    local TIMESTAMP=$(date +%Y-%m-%d-%H%M)
    local BACKUP_FILE="$BACKUP_DESTINATION/backup-$TIMESTAMP.tar.gz"
    local CHECKSUM_FILE="$BACKUP_FILE.sha256"

    local START_TIME=$(date +%s)
    log "INFO: Starting backup of $SOURCE_DIR"

    tar --exclude=".git" --exclude="node_modules" --exclude=".cache" -czf "$BACKUP_FILE" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"
    if [ $? -ne 0 ]; then
        log "ERROR: Backup failed during compression."
        exit 1
    fi

    sha256sum "$BACKUP_FILE" > "$CHECKSUM_FILE"
    local END_TIME=$(date +%s)
    local SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    local DURATION=$((END_TIME - START_TIME))

    log "SUCCESS: Backup created: $(basename "$BACKUP_FILE") (Size: $SIZE, Time: ${DURATION}s)"

    verify_backup "$BACKUP_FILE"
}

# === Verify backup ===
verify_backup() {
    local FILE=$1
    local CHECKSUM_FILE="$FILE.sha256"

    if [ ! -f "$FILE" ]; then
        log "ERROR: Backup file not found: $FILE"
        exit 1
    fi
    if [ ! -f "$CHECKSUM_FILE" ]; then
        log "ERROR: Checksum file not found: $CHECKSUM_FILE"
        exit 1
    fi

    log "INFO: Verifying existing backup: $FILE"
    sha256sum -c "$CHECKSUM_FILE" --status
    if [ $? -eq 0 ]; then
        log "SUCCESS: Backup verified successfully."
    else
        log "ERROR: Backup verification failed!"
    fi
}

# === List backups ===
list_backups() {
    log "INFO: Listing all backups in $BACKUP_DESTINATION"
    ls -lh "$BACKUP_DESTINATION" | grep "backup-" | tee -a "$LOG_FILE"
}

# === Restore backup ===
restore_backup() {
    local FILE=$1
    local DEST_DIR=$2

    if [ ! -f "$FILE" ]; then
        log "ERROR: Backup file not found: $FILE"
        exit 1
    fi

    mkdir -p "$DEST_DIR"
    log "INFO: Restoring backup $FILE to $DEST_DIR"
    tar -xzf "$FILE" -C "$DEST_DIR"
    if [ $? -eq 0 ]; then
        log "SUCCESS: Backup restored to $DEST_DIR"
    else
        log "ERROR: Failed to restore backup."
    fi
}

# === Parse arguments ===
case "$1" in
    --verify-only)
        verify_backup "$2"
        ;;
    --list)
        list_backups
        ;;
    --restore)
        restore_backup "$2" "$4"  # expects --restore <file> --to <folder>
        ;;
    *)
        create_backup "$1"
        ;;
esac
