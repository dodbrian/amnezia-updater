# Amnezia Updater

A CLI tool for managing Amnezia VPN (Xray-core) deployments on a remote VPS via SSH.

## Overview

Amnezia Updater automates the deployment and maintenance of Amnezia VPN servers running Xray-core in Docker containers. It provides commands for building, updating, backing up, and restoring VPN configurations.

**Important:** This tool is only for updating an existing Amnezia VPN installation. It cannot install Amnezia VPN from scratch. You must first install Amnezia VPN using the [official Amnezia client](https://amnezia.org/download) (mobile app or desktop application) on your VPS before using this tool.

## Requirements

- `ssh` and `scp` on the local machine

## Installation

Download the au.sh script:

```bash
curl -fsSL https://raw.githubusercontent.com/dodbrian/amnezia-updater/main/au.sh -o au.sh
chmod +x au.sh
```

## Quick Start

This tool assumes you already have an Amnezia VPN installation on your VPS (installed via the official Amnezia client).

1. Configure your VPS connection:

```bash
./au.sh config
```

2. Build the Docker image with a specific Xray version:

```bash
./au.sh build v25.8.3
```

Or build with the latest Xray release:

```bash
./au.sh build --latest
```

3. Update the running container (preserves keys and configuration):

```bash
./au.sh update
```

## Commands

| Command | Description |
|---------|-------------|
| `./au.sh config` | Configure default server and SSH port |
| `./au.sh build <version\|--latest>` | Build amnezia-xray image on remote VPS |
| `./au.sh update` | Recreate container from existing image and restore config |
| `./au.sh backup` | Archive and backup files from container |
| `./au.sh restore <archive>` | Restore files from backup archive |
| `./au.sh version` | Show deployed and latest Xray versions |

## Options

- `-s, --server <host>` - Override configured server for current command
- `-p, --port <port>` - Override configured SSH port (default: 22)
- `-h, --help` - Show help message

## Configuration

Configuration is stored in `~/.config/amnezia-updater/config`:

```
REMOTE_HOST=your-vps.example.com
REMOTE_PORT=22
```

## Prerequisites

Your remote VPS must already have Amnezia VPN installed (via the official Amnezia client). The installer sets up Docker, creates the necessary directory structure, and deploys the initial container.

The VPS must also have:

- SSH access with key-based authentication
- The following directory structure:
  - `/opt/amnezia/amnezia-xray/Dockerfile` - The Docker image definition

## Docker Image

The Dockerfile builds an Alpine Linux container with:

- Xray-core (configurable version via `XRAY_RELEASE` ARG)
- Optimized network settings (BBR, TCP tuning)
- dumb-init for proper signal handling

### Building Locally

```bash
docker build -t amnezia-xray .
```

### Exposed Ports

- `4433/tcp` - VPN traffic

## Security Considerations

- Backup archives contain sensitive VPN keys - store securely

## Examples

### Check current Xray version

```bash
./au.sh version
```

Output:
```
Deployed Xray version: v25.8.3
Latest Xray release:  v26.2.6
```

### Manual backup

```bash
./au.sh backup
```

Creates `amnezia-xray-backup-YYYYMMDD-HHMMSS.tar.gz` in current directory.

### Restore from backup

```bash
./au.sh restore amnezia-xray-backup-20240101-120000.tar.gz
```

### Deploy on custom port

```bash
./au.sh -s myserver.com -p 2222 build --latest
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
