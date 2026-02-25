#!/bin/bash

set -e

REMOTE_HOST="amnezia"
CONTAINER_NAME="amnezia-xray"
CONTAINER_PATH="/opt/amnezia/xray"

usage() {
    echo "Usage: $0 <command> [archive]"
    echo ""
    echo "Commands:"
    echo "  backup             - Archive and backup files from /opt/amnezia/xray in the container"
    echo "  restore <archive>   - Restore files from specified local archive to /opt/amnezia/xray in the container"
    exit 1
}

check_container() {
    if ! ssh "$REMOTE_HOST" "docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'"; then
        echo "Error: Container $CONTAINER_NAME is not running"
        exit 1
    fi
}

backup() {
    echo "Backing up files from $CONTAINER_NAME:$CONTAINER_PATH..."
    
    ARCHIVE_NAME="amnezia-xray-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    REMOTE_TMP_DIR="/tmp/amnezia-backup-$$"
    
    ssh "$REMOTE_HOST" "mkdir -p $REMOTE_TMP_DIR"
    
    ssh "$REMOTE_HOST" "docker cp ${CONTAINER_NAME}:${CONTAINER_PATH}/. $REMOTE_TMP_DIR/"
    
    ssh "$REMOTE_HOST" "cd $REMOTE_TMP_DIR && tar --exclude='*.tar.gz' -czf /tmp/$ARCHIVE_NAME . && rm -rf $REMOTE_TMP_DIR"
    
    scp "$REMOTE_HOST:/tmp/$ARCHIVE_NAME" "./"
    
    ssh "$REMOTE_HOST" "rm -f /tmp/$ARCHIVE_NAME"
    
    echo "Backup completed: ./$ARCHIVE_NAME"
    ls -la "./$ARCHIVE_NAME"
}

validate_archive() {
    local archive="$1"
    
    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        echo "Error: Invalid or corrupt archive: $archive"
        exit 1
    fi
    
    if ! tar -tzf "$archive" 2>&1 | grep -q "xray"; then
        echo "Error: Archive does not appear to be a valid xray backup"
        exit 1
    fi
}

restore() {
    if [ $# -lt 1 ]; then
        echo "Error: No archive file specified"
        usage
    fi
    
    ARCHIVE_FILE="$1"
    
    if [ ! -f "$ARCHIVE_FILE" ]; then
        echo "Error: Archive file not found: $ARCHIVE_FILE"
        exit 1
    fi
    
    validate_archive "$ARCHIVE_FILE"
    
    echo "Restoring files to $CONTAINER_NAME:$CONTAINER_PATH from $ARCHIVE_FILE..."
    
    REMOTE_TMP_DIR="/tmp/amnezia-restore-$$"
    
    ssh "$REMOTE_HOST" "mkdir -p $REMOTE_TMP_DIR"
    
    scp "$ARCHIVE_FILE" "$REMOTE_HOST:$REMOTE_TMP_DIR/"
    
    ARCHIVE_BASENAME=$(basename "$ARCHIVE_FILE")
    
    ssh "$REMOTE_HOST" "cd $REMOTE_TMP_DIR && tar -xzf $ARCHIVE_BASENAME && rm -f $ARCHIVE_BASENAME && docker cp . ${CONTAINER_NAME}:${CONTAINER_PATH}/ && rm -rf $REMOTE_TMP_DIR"
    
    echo "Restore completed"
}

if [ $# -lt 1 ]; then
    usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
    backup)
        check_container
        backup
        ;;
    restore)
        check_container
        restore "$@"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac