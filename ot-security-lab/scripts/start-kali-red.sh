#!/usr/bin/env bash
# Start (or restart) the kali-red container with the canonical flags.
set -euo pipefail

CONTAINER="${KALI_CONTAINER:-kali-red}"
IMAGE="${KALI_IMAGE:-kali-red:latest}"
MOUNT_SRC="${KALI_ENGAGEMENTS:-$HOME/engagements}"

mkdir -p "$MOUNT_SRC"

if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "[+] Removing existing container '$CONTAINER'..."
  docker rm -f "$CONTAINER" >/dev/null
fi

echo "[+] Starting '$CONTAINER' from image '$IMAGE'..."
docker run -d \
  --name "$CONTAINER" \
  --network host \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -v "$MOUNT_SRC:/engagements" \
  --restart unless-stopped \
  "$IMAGE" sleep infinity >/dev/null

echo "[+] Verifying..."
docker ps --filter "name=$CONTAINER" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

cat <<EOF

[✓] kali-red is up.
    Engagements:  $MOUNT_SRC  ->  /engagements
    Wrapper:      install with: sudo install -m 0755 scripts/kali /usr/local/bin/kali
    Shell:        kali
    One-shot:     kali nmap -sV -p 502 <target-ip>
EOF
