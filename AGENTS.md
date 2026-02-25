# AGENTS.md - Amnezia VPN Automation

This repository contains infrastructure-as-code for deploying and automating Amnezia VPN updates on a VPS.

## Project Overview

- Purpose: Deploy and automate Amnezia VPN with Xray-core on a remote VPS
- Remote Access: `ssh amnezia`
- Stack: Docker, Alpine Linux, Xray-core

## Build/Deploy Commands

### Build Docker Image
```bash
docker build -t amnezia-xray .
```

### Deploy with Docker Compose
```bash
docker-compose up -d --build
```

### Deploy on Remote VPS
```bash
ssh amnezia "cd /path/to/amnezia && docker-compose up -d --build"
```

### View Logs
```bash
docker logs amnezia-xray -f
```

### Stop Services
```bash
docker-compose down
```

### Update Xray Version
Update the `XRAY_RELEASE` ARG in Dockerfile (line 5) to the desired version tag from:
https://github.com/XTLS/Xray-core/releases

## Testing

This is an infrastructure repository with no automated tests. Manual verification steps:

1. Check container is running: `docker ps | grep amnezia-xray`
2. Check port is listening: `netstat -tlnp | grep 4433`
3. Test VPN connectivity from a client

## Code Style Guidelines

### Dockerfile Conventions

- Use Alpine Linux as base image for minimal footprint
- Pin versions explicitly (e.g., `alpine:3.15`, `XRAY_RELEASE=v26.2.6`)
- Combine RUN commands with `&&` to minimize layers
- Use LABEL for metadata and maintainer info
- Set environment variables with ENV directive
- Use dumb-init as entrypoint for proper signal handling
- Clean up temporary files in the same RUN layer
- Quote strings in scripts to prevent word splitting

### docker-compose.yml Conventions

- Use version 3.x compose file format (implicit in modern Docker)
- Name services descriptively (e.g., `amnezia-xray`)
- Use `restart: always` for production services
- Define custom networks with explicit subnet/gateway
- Use `privileged: true` and `NET_ADMIN` capability only when required
- Expose only necessary ports

### General Infrastructure Style

- Use meaningful container names
- Document any security-sensitive configurations (privileged mode, capabilities)
- Keep configuration values (ports, versions) as variables or clearly commented
- Follow 2-space indentation in YAML files
- Quote strings that contain special characters

## Repository Structure

```
/home/denis/source/amnezia/
├── Dockerfile           # Container definition for Amnezia Xray
├── docker-compose.yml   # Service orchestration
└── AGENTS.md           # This file
```

## VPS Access

The VPS is accessible via SSH alias:
```bash
ssh amnezia
```

When making changes:
1. Test locally if possible
2. Deploy to VPS via SSH for production testing
3. Verify service health after deployment

## Version Updates

To update Xray-core:

1. Check latest release: https://github.com/XTLS/Xray-core/releases
2. Update `XRAY_RELEASE` ARG in Dockerfile
3. Rebuild and redeploy

## Security Considerations

- The container runs in privileged mode with NET_ADMIN capability
- Port 4433 is exposed for VPN traffic
- Custom bridge network `amn0` is created for isolation
- System-level configurations (sysctl, limits) are applied for performance

## Troubleshooting

```bash
# Check container status
ssh amnezia "docker ps -a | grep amnezia"

# View container logs
ssh amnezia "docker logs amnezia-xray --tail 100"

# Check Xray binary
ssh amnezia "docker exec amnezia-xray xray version"

# Verify network
ssh amnezia "docker network inspect amnezia-dns-net"
```

## Notes for Agents

- This is infrastructure, not application code - no lint/tests to run
- Always verify deployment success after changes
- Check Xray-core releases for security updates
- The VPS uses SSH key authentication (alias: amnezia)