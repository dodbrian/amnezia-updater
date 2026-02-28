#!/bin/bash

set -e

TOOL_NAME="Amnezia Updater"
DEFAULT_PORT="22"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/amnezia-updater"
CONFIG_FILE="$CONFIG_DIR/config"

REMOTE_HOST=""
REMOTE_PORT=""
CONTAINER_NAME="amnezia-xray"
CONTAINER_PATH="/opt/amnezia/xray"

usage() {
    echo "$TOOL_NAME"
    echo "Usage: $0 [--server <host>] [--port <port>] <command> [args]"
    echo ""
    echo "Commands:"
    echo "  backup             - Archive and backup files from /opt/amnezia/xray in the container"
    echo "  restore <archive>  - Restore files from specified local archive to /opt/amnezia/xray in the container"
    echo "  build <version|--latest> - Build amnezia-xray image on remote VPS using remote Dockerfile"
    echo "  update             - Recreate amnezia-xray container from existing image and restore keys/config"
    echo "  version            - Show deployed Xray version and latest available GitHub release"
    echo "  config             - Configure default server and SSH port"
    echo ""
    echo "Global options:"
    echo "  --server, -s <host> - Override configured server for current command"
    echo "  --port, -p <port>   - Override configured SSH port for current command"
    exit 1
}

validate_port() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Error: Invalid port '$port' (expected 1-65535)"
        exit 1
    fi
}

save_config() {
    local host="$1"
    local port="$2"

    mkdir -p "$CONFIG_DIR"
    {
        printf 'REMOTE_HOST=%q\n' "$host"
        printf 'REMOTE_PORT=%q\n' "$port"
    } >"$CONFIG_FILE"

    chmod 600 "$CONFIG_FILE"
    echo "Saved configuration to $CONFIG_FILE"
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
    return 0
}

config_command() {
    local host
    local port
    local input_port

    read -rp "Server address: " host
    if [ -z "$host" ]; then
        echo "Error: Server address cannot be empty"
        exit 1
    fi

    read -rp "SSH port [$DEFAULT_PORT]: " input_port
    port="${input_port:-$DEFAULT_PORT}"
    validate_port "$port"

    save_config "$host" "$port"
}

ensure_remote_settings() {
    local cli_host="$REMOTE_HOST"
    local cli_port="$REMOTE_PORT"

    if [ -z "$cli_host" ] || [ -z "$cli_port" ]; then
        load_config || true
    fi

    if [ -n "$cli_host" ]; then
        REMOTE_HOST="$cli_host"
    fi

    if [ -n "$cli_port" ]; then
        REMOTE_PORT="$cli_port"
    fi

    if [ -z "$REMOTE_HOST" ]; then
        echo "No server configuration found. Launching config setup..."
        config_command
        load_config
    fi

    if [ -z "$REMOTE_PORT" ]; then
        REMOTE_PORT="$DEFAULT_PORT"
    fi

    validate_port "$REMOTE_PORT"
}

remote_ssh() {
    ssh -p "$REMOTE_PORT" "$REMOTE_HOST" "$@"
}

remote_scp_from() {
    local remote_path="$1"
    local local_path="$2"
    scp -P "$REMOTE_PORT" "$REMOTE_HOST:$remote_path" "$local_path"
}

remote_scp_to() {
    local local_path="$1"
    local remote_path="$2"
    scp -P "$REMOTE_PORT" "$local_path" "$REMOTE_HOST:$remote_path"
}

check_container() {
    if ! remote_ssh "docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'"; then
        echo "Error: Container $CONTAINER_NAME is not running"
        exit 1
    fi
}

backup() {
    echo "Backing up files from $CONTAINER_NAME:$CONTAINER_PATH..."
    
    ARCHIVE_NAME="amnezia-xray-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    REMOTE_TMP_DIR="/tmp/amnezia-backup-$$"
    
    remote_ssh "mkdir -p $REMOTE_TMP_DIR"
    
    remote_ssh "docker cp ${CONTAINER_NAME}:${CONTAINER_PATH}/. $REMOTE_TMP_DIR/"
    
    remote_ssh "cd $REMOTE_TMP_DIR && tar --exclude='*.tar.gz' -czf /tmp/$ARCHIVE_NAME . && rm -rf $REMOTE_TMP_DIR"
    
    remote_scp_from "/tmp/$ARCHIVE_NAME" "./"
    
    remote_ssh "rm -f /tmp/$ARCHIVE_NAME"
    
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
    
    remote_ssh "mkdir -p $REMOTE_TMP_DIR"
    
    remote_scp_to "$ARCHIVE_FILE" "$REMOTE_TMP_DIR/"
    
    ARCHIVE_BASENAME=$(basename "$ARCHIVE_FILE")
    
    remote_ssh "cd $REMOTE_TMP_DIR && tar -xzf $ARCHIVE_BASENAME && rm -f $ARCHIVE_BASENAME && docker cp . ${CONTAINER_NAME}:${CONTAINER_PATH}/ && rm -rf $REMOTE_TMP_DIR"
    
    echo "Restore completed"
}

resolve_latest_xray_release() {
    local response
    local latest

    response=$(curl -fsSL "https://api.github.com/repos/XTLS/Xray-core/releases/latest")
    latest=$(printf '%s\n' "$response" | sed -nE 's/^[[:space:]]*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' | head -n1)

    if [ -z "$latest" ]; then
        echo "Error: Failed to resolve latest Xray release"
        exit 1
    fi

    echo "$latest"
}

build() {
    if [ $# -ne 1 ]; then
        echo "Error: build requires exactly one argument: <version|--latest>"
        usage
    fi

    local requested_version="$1"
    local release_version
    local remote_build_dir="/opt/amnezia/amnezia-xray"
    local remote_dockerfile="$remote_build_dir/Dockerfile"

    if [ "$requested_version" = "--latest" ]; then
        release_version=$(resolve_latest_xray_release)
        echo "Resolved latest Xray release: $release_version"
    else
        release_version="$requested_version"
    fi

    if ! [[ "$release_version" =~ ^v ]]; then
        echo "Error: XRAY_RELEASE must start with 'v' (example: v25.8.3)"
        exit 1
    fi

    if ! remote_ssh "test -f $remote_dockerfile"; then
        echo "Error: Remote Dockerfile not found: $remote_dockerfile"
        exit 1
    fi

    if ! remote_ssh "grep -q '^ARG XRAY_RELEASE=' $remote_dockerfile"; then
        echo "Error: Remote Dockerfile does not contain ARG XRAY_RELEASE"
        exit 1
    fi

    echo "Building amnezia-xray image on $REMOTE_HOST with XRAY_RELEASE=$release_version..."
    remote_ssh "docker build --no-cache --pull --build-arg XRAY_RELEASE=$release_version -t amnezia-xray $remote_build_dir"

    echo "Build completed on $REMOTE_HOST"
}

update() {
    local image_name="amnezia-xray"
    local archive_file
    local old_container_name
    local remote_startup_backup

    if [ $# -ne 0 ]; then
        echo "Error: update does not accept arguments"
        usage
    fi

    if ! remote_ssh "docker image inspect $image_name >/dev/null 2>&1"; then
        echo "Error: Image $image_name not found on $REMOTE_HOST"
        exit 1
    fi

    check_container

    echo "Creating pre-update backup..."
    backup
    archive_file="./$ARCHIVE_NAME"

    old_container_name="${CONTAINER_NAME}-old-$(date +%Y%m%d-%H%M%S)"
    remote_startup_backup="/tmp/amnezia-startup-$$.sh"

    echo "Stopping existing container and preserving it as $old_container_name..."
    remote_ssh "docker stop $CONTAINER_NAME && docker rename $CONTAINER_NAME $old_container_name"

    echo "Backing up startup script from preserved container..."
    remote_ssh "if docker cp ${old_container_name}:/opt/amnezia/start.sh $remote_startup_backup 2>/dev/null; then echo 'Startup script backup created'; else echo 'Warning: /opt/amnezia/start.sh not found in old container, image default will be used'; fi"

    echo "Creating new container from existing image..."
    remote_ssh "docker run -d --privileged --log-driver none --restart always --cap-add=NET_ADMIN -p 4433:4433/tcp --name $CONTAINER_NAME $image_name"

    echo "Connecting container to amnezia-dns-net..."
    remote_ssh "docker network connect amnezia-dns-net $CONTAINER_NAME"

    echo "Ensuring TUN device exists on host..."
    remote_ssh "mkdir -p /dev/net && (test -c /dev/net/tun || mknod /dev/net/tun c 10 200)"

    echo "Restoring startup script into new container (Phase 10 parity)..."
    remote_ssh "if [ -f $remote_startup_backup ]; then docker cp $remote_startup_backup ${CONTAINER_NAME}:/opt/amnezia/start.sh && rm -f $remote_startup_backup; fi"

    echo "Restoring keys and configuration into new container..."
    restore "$archive_file"

    echo "Restarting container..."
    remote_ssh "docker restart $CONTAINER_NAME"

    echo "Checking new container stability..."
    remote_ssh "for i in 1 2 3; do sleep 5; if [ \"\$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)\" != \"true\" ]; then exit 1; fi; done"

    echo "New container is stable. Removing preserved old container $old_container_name..."
    remote_ssh "docker rm -fv $old_container_name"

    echo "Update completed successfully"
    echo "Backup archive retained at: $archive_file"
}

version() {
    local deployed_version
    local latest_version

    if [ $# -ne 0 ]; then
        echo "Error: version does not accept arguments"
        usage
    fi

    check_container

    deployed_version=$(remote_ssh "docker exec $CONTAINER_NAME xray version 2>/dev/null | awk 'NR==1 { print \$2; exit }'")
    if [ -z "$deployed_version" ]; then
        echo "Error: Failed to determine deployed Xray version from $CONTAINER_NAME"
        exit 1
    fi

    latest_version=$(resolve_latest_xray_release)

    echo "Deployed Xray version: $deployed_version"
    echo "Latest Xray release:  $latest_version"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -s|--server)
            if [ $# -lt 2 ]; then
                echo "Error: $1 requires a value"
                usage
            fi
            REMOTE_HOST="$2"
            shift 2
            ;;
        -p|--port)
            if [ $# -lt 2 ]; then
                echo "Error: $1 requires a value"
                usage
            fi
            REMOTE_PORT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -* )
            echo "Unknown option: $1"
            usage
            ;;
        * )
            break
            ;;
    esac
done

if [ $# -lt 1 ]; then
    usage
fi

COMMAND="$1"
shift

if [ "$COMMAND" = "config" ]; then
    if [ $# -ne 0 ]; then
        echo "Error: config does not accept arguments"
        usage
    fi
    config_command
    exit 0
fi

ensure_remote_settings

case "$COMMAND" in
    backup)
        check_container
        backup
        ;;
    restore)
        check_container
        restore "$@"
        ;;
    build)
        build "$@"
        ;;
    update)
        update "$@"
        ;;
    version)
        version "$@"
        ;;
    config)
        config_command
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac
