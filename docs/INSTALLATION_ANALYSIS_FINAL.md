# AmneziaVPN Xray-Core Installation Process - Complete Analysis

**Log File:** `amnezia-installaion-history.log` (340 lines)  
**Date:** Wed Feb 25 21:05:21 2026  
**Protocol:** VLESS + Reality  
**Port:** 4433/TCP  
**System:** Ubuntu/Debian (detected via apt-get)  
**Xray Version:** v25.8.3 (Alpine Linux 3.15 base)

---

## Overview

This log captures a complete, automated AmneziaVPN deployment orchestrated by the Amnezia desktop client via SSH. The installation:

1. Detects and verifies system dependencies (Docker, package manager, network tools)
2. Creates isolated Docker infrastructure (custom network, volume directories)
3. Builds a containerized Xray-core VPN server with Reality protocol stealth
4. Generates cryptographic keys (X25519, UUIDs, short IDs)
5. Applies host-level kernel tuning for high-performance networking
6. Deploys firewall rules (both host and container level)
7. Initializes a client database with admin credentials
8. Performs secure cleanup of temporary files

---

## Phase 1: Session Initialization (Lines 1-10)

Standard Ubuntu MOTD system identification scripts run when root logs in via SSH.

**Commands executed:**
```
run-parts --lsbsysinit /etc/update-motd.d
├── 00-header       → System info (uname -o, -r, -m)
├── 10-help-text
├── 50-motd-news
├── 91-contract-ua-esm-status
└── 92-unattended-upgrades → Update availability
```

---

## Phase 2: Environment Detection (Lines 11-75)

### 2.1 Docker Container Enumeration
```bash
docker ps --format '{{.Names}} {{.Ports}}'
```
Lists any existing containers to detect prior installations.

### 2.2 Package Manager Auto-Detection
```bash
if which apt-get > /dev/null 2>&1
  → DETECTED: /usr/bin/apt-get (Debian/Ubuntu)
  pm=/usr/bin/apt-get
  silent_inst="-yq install"
  check_pkgs="-yq update"
  docker_pkg="docker.io"
elif which dnf > /dev/null 2>&1   # Fedora
elif which yum > /dev/null 2>&1   # CentOS
elif which zypper > /dev/null 2>&1 # openSUSE
elif which pacman > /dev/null 2>&1 # Arch
```

**Result:** `apt-get` found → **Debian/Ubuntu system confirmed**

### 2.3 Locale Configuration
Checks if locale is compatible. If not, sets `LC_ALL=C` for consistent output.

### 2.4 Lock File Check
```bash
fuser /var/lib/dpkg/lock-frontend
```
Ensures no concurrent apt-get processes are running.

### 2.5 Dependency Verification

| Tool | Purpose | Install if Missing |
|------|---------|-------------------|
| `sudo` | Privilege escalation | `apt-get -yq install sudo` |
| `fuser` | Lock file detection | `apt-get -yq install psmisc` |
| `lsof` | Port enumeration | `apt-get -yq install lsof` |
| `docker` | Container runtime | `apt-get -yq install docker.io` |
| `apparmor_parser` | Optional (if AppArmor) | `apt-get -yq install apparmor` |

**Docker status confirmation:**
```bash
docker --version
systemctl is-active docker
```

---

## Phase 3: Pre-Installation Port Check (Lines 76-89)

Verifies port 4433 is not already in use.

```bash
lsof -i -P -n 2>/dev/null | grep -E ':4433 ' | grep -i tcp | grep LISTEN
```

**Result:** No output = **Port 4433 is free**

---

## Phase 4: Infrastructure Setup (Lines 90-108)

### 4.1 Directory Creation
```bash
mkdir -p /opt/amnezia/amnezia-xray
chown root /opt/amnezia/amnezia-xray
```

Creates base directory for VPN installation files.

### 4.2 Docker Network Creation
```bash
docker network create \
  --driver bridge \
  --subnet=172.29.172.0/24 \
  --opt com.docker.network.bridge.name=amn0 \
  amnezia-dns-net
```

Creates isolated Layer 2 bridge network for VPN services with:
- **Subnet:** 172.29.172.0/24 (254 usable IPs)
- **Bridge interface:** amn0
- **Purpose:** Container isolation from default Docker bridge

---

## Phase 5: Cleanup of Previous Installation (Lines 109-120)

```bash
docker stop amnezia-xray        # Graceful shutdown
docker rm -fv amnezia-xray      # Remove container + volumes
docker rmi amnezia-xray         # Remove image
rm /opt/amnezia/amnezia-xray/Dockerfile
```

Ensures clean slate for new deployment. Removes stale containers, images, and configurations.

---

## Phase 6: Docker Image Build (Lines 121-125)

### 6.1 Dockerfile Transfer
```bash
scp -t /opt/amnezia/amnezia-xray/Dockerfile
```

Receives Dockerfile from Amnezia client (generated dynamically).

### 6.2 Image Build
```bash
docker build --no-cache --pull -t amnezia-xray /opt/amnezia/amnezia-xray
```

Build options:
- `--no-cache` - Don't use cached layers (fresh build)
- `--pull` - Always pull base image (latest updates)

### Dockerfile Analysis

**Base:** Alpine Linux 3.15 (minimal 5MB footprint)

**Xray Release:** v25.8.3 (installed from GitHub releases)

**Dependencies Installed:**
```
curl unzip bash openssl netcat-openbsd dumb-init rng-tools xz
```

| Package | Purpose |
|---------|---------|
| `curl` | Download Xray binary |
| `unzip` | Extract Xray archive |
| `bash` | Script execution |
| `openssl` | Cryptography utilities |
| `netcat-openbsd` | Network diagnostics |
| `dumb-init` | Signal handling (PID 1) |
| `rng-tools` | Entropy generation |
| `xz` | Compression support |

**Xray Installation:**
```bash
curl -L https://github.com/XTLS/Xray-core/releases/download/v25.8.3/Xray-linux-64.zip > /root/xray.zip
unzip /root/xray.zip -d /usr/bin/
chmod a+x /usr/bin/xray
```

**Kernel Tuning (Embedded in Image):**
The Dockerfile includes sysctl parameters that are baked into `/etc/sysctl.conf`:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `fs.file-max` | 51200 | Max open file descriptors |
| `net.core.rmem_max` | 67108864 (64MB) | Max receive buffer |
| `net.core.wmem_max` | 67108864 (64MB) | Max send buffer |
| `net.core.netdev_max_backlog` | 250000 | Input queue depth |
| `net.core.somaxconn` | 4096 | Max pending connections |
| `net.core.default_qdisc` | fq | Fair Queue scheduler |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |
| `net.ipv4.tcp_tw_reuse` | 1 | Reuse TIME_WAIT sockets |
| `net.ipv4.tcp_tw_recycle` | 0 | Disabled (deprecated) |
| `net.ipv4.tcp_fin_timeout` | 30 | FIN_WAIT_2 timeout |
| `net.ipv4.tcp_keepalive_time` | 1200 | Keepalive interval |
| `net.ipv4.ip_local_port_range` | 10000-65000 | Ephemeral port range |
| `net.ipv4.tcp_max_syn_backlog` | 8192 | SYN queue size |
| `net.ipv4.tcp_max_tw_buckets` | 5000 | Max TIME_WAIT sockets |
| `net.ipv4.tcp_fastopen` | 3 | TCP Fast Open (both sides) |
| `net.ipv4.tcp_mem` | 25600 51200 102400 | TCP memory limits |
| `net.ipv4.tcp_rmem` | 4096 87380 67108864 | Receive buffer (min/default/max) |
| `net.ipv4.tcp_wmem` | 4096 65536 67108864 | Send buffer (min/default/max) |
| `net.ipv4.tcp_mtu_probing` | 1 | Path MTU discovery |
| `net.ipv4.tcp_congestion_control` | **bbr** | Bottleneck Bandwidth & RTT |

**Important Discovery:** The Dockerfile specifies `bbr` congestion control (not `hybla` as the host sysctl applies later). This is a key difference:

| Algorithm | Optimized For | Characteristics |
|-----------|---------------|-----------------|
| **BBR** (in image) | High-bandwidth links | Model-based, responds to packet loss |
| **HYBLA** (host sysctl) | High-latency links | Aggressively expands window |

The container uses BBR; the host layer-2 may override to HYBLA.

**File Descriptor Limits (also in image):**
```bash
* soft nofile 51200
* hard nofile 51200
```
Configured in `/etc/security/limits.conf` for root user.

**Timezone:**
```
ENV TZ=Asia/Shanghai
```

**Entrypoint:**
```bash
ENTRYPOINT [ "dumb-init", "/opt/amnezia/start.sh" ]
```

Uses `dumb-init` wrapper to handle signals properly (converts host signals to child processes).

---

## Phase 7: Container Deployment (Lines 126-141)

### 7.1 Container Launch
```bash
docker run -d \
  --privileged \
  --log-driver none \
  --restart always \
  --cap-add=NET_ADMIN \
  -p 4433:4433/tcp \
  --name amnezia-xray \
  amnezia-xray
```

**Runtime flags:**

| Flag | Purpose | Security Impact |
|------|---------|-----------------|
| `-d` | Detached mode | Low |
| `--privileged` | Full kernel capabilities | **HIGH** - Full system access |
| `--log-driver none` | Disable logging | Audit consideration |
| `--restart always` | Auto-restart on failure/reboot | Operational resilience |
| `--cap-add=NET_ADMIN` | Network administration | Medium - Required for VPN |
| `-p 4433:4433/tcp` | Port mapping | Exposes port publicly |

### 7.2 Network Attachment
```bash
docker network connect amnezia-dns-net amnezia-xray
```

Container gets IP on 172.29.172.0/24 subnet.

### 7.3 TUN Device Creation
```bash
mkdir -p /dev/net
mknod /dev/net/tun c 10 200
```

Creates TUN character device (major:10, minor:200) required for VPN tunneling.

---

## Phase 8: Xray Key Generation (Lines 142-164)

**Script:** `ueSPWOk3ajQV09uG.tmp` → `/opt/amnezia/b76nVmoFdOsYwQEy.sh`

### Key Generation Workflow

```bash
cd /opt/amnezia/xray

# 1. Generate client UUID (RFC 4122)
XRAY_CLIENT_ID=$(xray uuid)
echo $XRAY_CLIENT_ID > xray_uuid.key

# 2. Generate Reality short ID (8 random hex bytes)
XRAY_SHORT_ID=$(openssl rand -hex 8)
echo $XRAY_SHORT_ID > xray_short_id.key

# 3. Generate X25519 keypair (elliptic curve)
KEYPAIR=$(xray x25519)
# Output format:
# PrivateKey: <base64>
# PublicKey:  <base64>

# 4. Parse and extract keys
while IFS= read -r line; do
  if [[ $LINE_NUM -gt 1 ]]; then
    IFS=":" read FIST XRAY_PUBLIC_KEY <<< "$line"
  else
    LINE_NUM=$((LINE_NUM + 1))
    IFS=":" read FIST XRAY_PRIVATE_KEY <<< "$line"
  fi
done <<< "$KEYPAIR"

# 5. Trim whitespace
XRAY_PRIVATE_KEY=$(echo $XRAY_PRIVATE_KEY | tr -d ' ')
XRAY_PUBLIC_KEY=$(echo $XRAY_PUBLIC_KEY | tr -d ' ')

# 6. Save keys
echo $XRAY_PUBLIC_KEY > xray_public.key
echo $XRAY_PRIVATE_KEY > xray_private.key

# 7. Generate server.json with embedded keys
cat > server.json <<EOF
{ ... configuration ... }
EOF
```

### Generated Artifacts

| File | Content |
|------|---------|
| `xray_uuid.key` | Client UUID (16 bytes, RFC 4122) |
| `xray_short_id.key` | Reality short ID (8 random hex bytes) |
| `xray_public.key` | X25519 public key (32 bytes, base64) |
| `xray_private.key` | X25519 private key (32 bytes, base64) |
| `server.json` | Xray server configuration |

### Initial server.json Template

```json
{
    "log": { "loglevel": "error" },
    "inbounds": [{
        "port": 4433,
        "protocol": "vless",
        "settings": {
            "clients": [{
                "id": "<GENERATED_UUID>",
                "flow": "xtls-rprx-vision"
            }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "dest": "www.googletagmanager.com:443",
                "serverNames": ["www.googletagmanager.com"],
                "privateKey": "<GENERATED_PRIVATE_KEY>",
                "shortIds": ["<GENERATED_SHORT_ID>"]
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
```

### Cryptography Explained

**VLESS Protocol:** Lightweight encrypted tunnel
- Minimal overhead
- No built-in encryption (delegated to Reality)
- `flow: xtls-rprx-vision` = optimized XTLS mode

**Reality Protocol:** TLS masquerading for censorship resistance
- Disguises VPN traffic as legitimate HTTPS
- **Private Key:** X25519 elliptic curve key
- **Public Key:** Derived from private key
- **Short ID:** 8-byte identifier preventing server fingerprinting
- **Destination:** www.googletagmanager.com:443

**Why googletagmanager.com?**
- Part of Google Analytics (ultra-high traffic)
- Consistently whitelisted by ISPs/firewalls worldwide
- TLS certificate valid for legitimate Google domains
- Censors cannot block without breaking millions of websites
- SNI/ALPN negotiation appears completely normal

### File Lifecycle (Secure Deletion Pattern)

```
1. scp -t /tmp/ueSPWOk3ajQV09uG.tmp
   └─ Script transferred from Amnezia client over encrypted SSH

2. cp /tmp/ueSPWOk3ajQV09uG.tmp /var/tmp-backups/ueSPWOk3ajQV09uG.tmp
   └─ Backup created (recovery safety)

3. stat -c%s /tmp/ueSPWOk3ajQV09uG.tmp
   └─ Verify file size (integrity check)

4. docker cp /tmp/ueSPWOk3ajQV09uG.tmp amnezia-xray://opt/amnezia/b76nVmoFdOsYwQEy.sh
   └─ Copy into container filesystem

5. docker exec -i amnezia-xray bash /opt/amnezia/b76nVmoFdOsYwQEy.sh
   └─ Execute script inside container (xray binary available)

6. docker exec -i amnezia-xray rm /opt/amnezia/b76nVmoFdOsYwQEy.sh
   └─ Delete script from container

7. shred -u /tmp/ueSPWOk3ajQV09uG.tmp
   └─ Securely overwrite host copy with random data
   └─ Unrecoverable even with forensic tools

8. [Backup remains in /var/tmp-backups/]
   └─ For disaster recovery
```

---

## Phase 9: Host System Tuning (Lines 165-245)

### 9.1 IP Forwarding
```bash
sysctl -w net.ipv4.ip_forward=1
```

Enables packet forwarding between network interfaces. Essential for VPN packet routing.

### 9.2 Firewall Configuration

#### Outbound Ping Blocking (Stealth)
```bash
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
```

Server doesn't respond to ping requests (ICMP). Makes server invisible to ping-based scanning.

#### Docker FORWARD Chain Setup
```bash
iptables -C FORWARD -j DOCKER-USER || iptables -A FORWARD -j DOCKER-USER
iptables -C FORWARD -j DOCKER-ISOLATION-STAGE-1 || iptables -A FORWARD -j DOCKER-ISOLATION-STAGE-1
iptables -C FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || ...
iptables -C FORWARD -o docker0 -j DOCKER || ...
iptables -C FORWARD -i docker0 ! -o docker0 -j ACCEPT || ...
iptables -C FORWARD -i docker0 -o docker0 -j ACCEPT || ...
```

Each rule uses `-C` (check) before `-A` (append) to avoid duplicates. These rules:
1. Insert custom DOCKER-USER chain
2. Insert isolation chain (container-to-container control)
3. Allow established connections outbound
4. Route Docker traffic through DOCKER chain
5. Allow inter-container communication

### 9.3 Host-Level Kernel Tuning

These parameters (from Phase 6 Dockerfile) are now applied at host level:

```bash
sysctl fs.file-max=51200
sysctl net.core.rmem_max=67108864
sysctl net.core.wmem_max=67108864
sysctl net.core.netdev_max_backlog=250000
sysctl net.core.somaxconn=4096
sysctl net.ipv4.tcp_syncookies=1
sysctl net.ipv4.tcp_tw_reuse=1
sysctl net.ipv4.tcp_tw_recycle=0
sysctl net.ipv4.tcp_fin_timeout=30
sysctl net.ipv4.tcp_keepalive_time=1200
sysctl net.ipv4.ip_local_port_range="10000 65000"
sysctl net.ipv4.tcp_max_syn_backlog=8192
sysctl net.ipv4.tcp_max_tw_buckets=5000
sysctl net.ipv4.tcp_fastopen=3
sysctl net.ipv4.tcp_mem="25600 51200 102400"
sysctl net.ipv4.tcp_rmem="4096 87380 67108864"
sysctl net.ipv4.tcp_wmem="4096 65536 67108864"
sysctl net.ipv4.tcp_mtu_probing=1
sysctl net.ipv4.tcp_congestion_control=hybla
```

**Note:** Host applies `hybla` congestion control (high-latency optimized), while container image defaults to `bbr`. This creates a hybrid optimization strategy.

---

## Phase 10: Startup Script Deployment (Lines 246-266)

**Script:** `WXYbTfXsL4pVXnHI.tmp` → `/opt/amnezia/start.sh`

Runs every time container starts:

```bash
#!/bin/bash

echo "Container startup"

# INPUT firewall rules (drop by default)
iptables -A INPUT -i lo -j ACCEPT
  └─ Allow loopback

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  └─ Allow established/related connections

iptables -A INPUT -p icmp -j ACCEPT
  └─ Allow ping

iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  └─ Allow HTTP

iptables -A INPUT -p tcp --dport 443 -j ACCEPT
  └─ Allow HTTPS

iptables -P INPUT DROP
  └─ Default policy: DROP all unlisted traffic

# IPv6 equivalent
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
ip6tables -P INPUT DROP

# Kill any existing xray process
killall -KILL xray
  └─ Handles container restart

# Start VPN server
if [ -f /opt/amnezia/xray/server.json ]; then
  xray -config /opt/amnezia/xray/server.json
fi

# Keep container alive
tail -f /dev/null
```

**Firewall Policy:**

| Chain | Default | Allow |
|-------|---------|-------|
| INPUT | DROP | loopback, established, ICMP, TCP/80, TCP/443 |
| IPv6 INPUT | DROP | loopback, established, ICMPv6 |

**Important:** Port 4433 is NOT explicitly allowed in container iptables. This is correct because Docker's host-level iptables handle the `4433:4433/tcp` port mapping before traffic reaches the container.

---

## Phase 11: Server Configuration Update (Lines 267-288)

**File:** `VQajDpI3p43eEf6I.tmp` → `/opt/amnezia/xray/server.json`

The initial server.json is replaced with finalized configuration:

```json
{
    "inbounds": [{
        "port": 4433,
        "protocol": "vless",
        "settings": {
            "clients": [
                {
                    "flow": "xtls-rprx-vision",
                    "id": "586c01a6-1732-4040-bd98-7a233ce9a6a3"
                },
                {
                    "flow": "xtls-rprx-vision",
                    "id": "5001cf3d-c557-4459-a069-47339bd32106"
                }
            ],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "realitySettings": {
                "dest": "www.googletagmanager.com:443",
                "privateKey": "*******************************************",
                "serverNames": ["www.googletagmanager.com"],
                "shortIds": ["****************"]
            },
            "security": "reality"
        }
    }],
    "log": { "loglevel": "error" },
    "outbounds": [{ "protocol": "freedom" }]
}
```

### Configuration Analysis

**Two clients:**
1. `586c01a6-1732-4040-bd98-7a233ce9a6a3` - Original from Phase 8 key generation
2. `5001cf3d-c557-4459-a069-47339bd32106` - Admin client (added in Phase 11)

Xray allows multiple clients per server instance. Both can authenticate with the same Reality parameters.

**Private Key & Short ID:** Fresh pair generated by Amnezia client (different from Phase 8).

### Container Restart
```bash
docker restart amnezia-xray
```

Container stops and restarts. The `/opt/amnezia/start.sh` script executes again, loading the NEW server.json with 2 clients.

---

## Phase 12: Credential Retrieval (Lines 289-306)

Amnezia client reads back all generated credentials for local storage.

```bash
xxd -p '/opt/amnezia/xray/server.json'
xxd -p '/opt/amnezia/xray/xray_public.key'
xxd -p '/opt/amnezia/xray/xray_short_id.key'
xxd -p '/opt/amnezia/xray/xray_uuid.key'
xxd -p '/opt/amnezia/xray/clientsTable'
```

**Why `xxd -p`?** Converts binary to continuous hex string (safe ASCII-only transfer over SSH without encoding issues). Amnezia client decodes hex back to binary locally.

---

## Phase 13: Client Database Setup (Lines 307-340)

### Update 1: `nWtNhyef3AY9YkaV.tmp` → `/opt/amnezia/xray/clientsTable`

```json
[
    {
        "clientId": "5001cf3d-c557-4459-a069-47339bd32106",
        "userData": {
            "clientName": "Client 0"
        }
    }
]
```

Initial placeholder entry.

### Update 2: `K4bdZTIByZSUQaPv.tmp` → `/opt/amnezia/xray/clientsTable`

```json
[
    {
        "clientId": "5001cf3d-c557-4459-a069-47339bd32106",
        "userData": {
            "clientName": "Admin [iOS 18.7]",
            "creationDate": "Wed Feb 25 21:05:21 2026"
        }
    }
]
```

Final state: Renamed with device information and timestamp.

### Client Database Evolution

| Version | Client Name | Change |
|---------|------------|--------|
| 1st | "Client 0" | Initial placeholder |
| 2nd | "Admin [iOS 18.7]" | User-configured device |

---

## Temporary Files Summary

| File | Size | Destination | Purpose |
|------|------|-------------|---------|
| `ueSPWOk3ajQV09uG.tmp` | ~2KB | `/opt/amnezia/b76nVmoFdOsYwQEy.sh` | Key generation script |
| `WXYbTfXsL4pVXnHI.tmp` | ~800B | `/opt/amnezia/start.sh` | Container startup |
| `VQajDpI3p43eEf6I.tmp` | ~1KB | `/opt/amnezia/xray/server.json` | Xray config |
| `nWtNhyef3AY9YkaV.tmp` | ~150B | `/opt/amnezia/xray/clientsTable` | Client DB (v1) |
| `K4bdZTIByZSUQaPv.tmp` | ~170B | `/opt/amnezia/xray/clientsTable` | Client DB (v2) |

All files follow secure deletion pattern:
1. Transferred via encrypted SSH
2. Backed up to `/var/tmp-backups/`
3. Size verified with `stat`
4. Copied into container
5. Used/executed
6. Securely shredded (`shred -u`)

---

## Security Properties

### Strengths
✓ Private keys generated inside container (never plaintext transmission)  
✓ Hex encoding for all credential transfers  
✓ Secure cleanup via `shred` (multiple overwrite passes)  
✓ Firewall defaults to DROP (whitelist approach)  
✓ Complete audit trail logged  

### Considerations
⚠ Container runs `--privileged` (full kernel access)  
⚠ NET_ADMIN capability allows network stack manipulation  
⚠ No container logging (`--log-driver none`)  
⚠ Backup files should be encrypted at rest  

---

## Final System State

| Component | Configuration |
|-----------|----------------|
| **Container** | `amnezia-xray` (running) |
| **Restart Policy** | Always (auto-restart on failure/reboot) |
| **Network** | `amnezia-dns-net` (172.29.172.0/24) |
| **Protocol** | VLESS + Reality |
| **Port** | 4433/TCP |
| **Masquerade** | www.googletagmanager.com:443 |
| **Active Clients** | 2 in server.json, 1 tracked in clientsTable |
| **Xray Version** | v25.8.3 (Alpine 3.15) |
| **Host Firewall** | IP forwarding enabled, DROP default |
| **Container Firewall** | INPUT DROP, allows lo/established/ICMP/80/443 |
| **Kernel Tuning** | VPN-optimized (64MB buffers, BBR/HYBLA, TCP_FASTOPEN) |

---

## Key Takeaways

1. **Fully Automated** - Amnezia client orchestrates entire deployment via SSH
2. **Security-First** - Keys generated inside container, secure file cleanup
3. **Performance Optimized** - Kernel parameters tuned for high-bandwidth VPN
4. **Stealth Protocol** - Reality masquerades as Google Analytics HTTPS
5. **Production Ready** - Auto-restart, firewall hardening, client management
6. **Audit Trail** - Complete command history preserved for compliance