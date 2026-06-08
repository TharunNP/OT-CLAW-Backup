# Setup Guide

Replicate this lab on a dedicated host. Estimated time: **30-45 minutes** (plus Docker image build).

---

## Prerequisites

### Hardware

- **CPU:** 4+ cores
- **RAM:** 4 GB minimum, 8 GB recommended
- **Disk:** 20 GB free (the `kali-red` image alone is ~5 GB)
- **Network:** wired Ethernet to the lab subnet (or virtual switch in a hypervisor)

### Software

- Linux host (Ubuntu 22.04 LTS or 24.04 LTS recommended; Debian 12 also tested)
- Docker Engine 24+
- Git
- Curl

### Network requirements

- An **isolated lab subnet** (e.g. `192.168.1.0/24`) that the host is on.
- **No route from the lab to the internet** for anything but explicit allowlist (apt updates from the host).
- If sharing a physical LAN: VLAN segmentation + firewall.

---

## Step 1 — Prepare the Host

### 1.1 — Install Docker

```bash
# Add Docker's official APT repo
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 1.2 — Add your user to the `docker` group

```bash
sudo usermod -aG docker $USER
```

⚠️ **You must fully log out and back in** for the group to take effect. If you cannot relog immediately, prefix docker commands with `sg docker -c "..."` as a stopgap.

### 1.3 — Verify

```bash
docker version
docker run --rm hello-world
```

---

## Step 2 — Clone This Repo

```bash
git clone https://github.com/<you>/ot-security-lab.git
cd ot-security-lab
```

---

## Step 3 — Build `kali-red`

```bash
docker build -t kali-red:latest docker/kali-red/
```

This downloads `kali:latest` and installs ~1.5 GB of tools. **Allow 5-15 minutes** depending on bandwidth.

When done:

```bash
docker images kali-red:latest
```

You should see the image listed at ~1.3 GB content / ~5 GB on-disk.

---

## Step 4 — Start the Lab Target

### Option A — Pymodbus simulator (recommended for first run)

```bash
docker compose -f docker/lab-target/compose.yml up -d
```

The simulator listens on `:502` on the host. Verify:

```bash
docker logs lab-target
nc -zv 127.0.0.1 502
```

### Option B — OpenPLC (more realistic, software PLC)

See [`docker/openplc/README.md`](../docker/openplc/README.md).

### Option C — Real PLC

Wire it to the lab switch, set a static IP within the lab subnet, and document its IP/model in `engagements/<name>/notes.md`. Nothing else to start.

---

## Step 5 — Start `kali-red`

Run the start script (it creates the container with the correct flags):

```bash
./scripts/start-kali-red.sh
```

This runs:

```bash
docker run -d --name kali-red \
  --network host \
  --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -v "$HOME/engagements:/engagements" \
  --restart unless-stopped \
  kali-red:latest sleep infinity
```

### Verify

```bash
docker ps --filter name=kali-red
```

You should see `kali-red` in the `Up` state.

---

## Step 6 — Install the `kali` Wrapper

```bash
sudo install -m 0755 scripts/kali /usr/local/bin/kali
```

Now `kali` is available globally:

```bash
kali --help              # or just `kali` for interactive shell
kali nmap --version
```

---

## Step 7 — Verify the Full Chain

```bash
# Tools available?
kali -c 'for t in nmap masscan hping3 tcpdump tshark hydra nikto msfconsole searchsploit ettercap bettercap arpspoof tcpreplay snmpwalk; do
  command -v $t >/dev/null && echo "OK   $t" || echo "MISS $t"
done'

# Python ICS stack?
kali -c 'for m in pymodbus pysnmp scapy cpppo opcua snap7 boofuzz; do
  python3 -c "import $m" 2>/dev/null && echo "OK   $m" || echo "MISS $m"
done'

# Can we reach the target?
TARGET_IP=192.168.1.95  # adjust to your simulator/PLC IP
kali nmap -Pn -p 502 --script modbus-discover $TARGET_IP
```

Expected output: device identification, slave IDs, vendor string.

---

## Step 8 — Create Your First Engagement Folder

```bash
mkdir -p ~/engagements/lab-baseline/{recon,enumeration,baseline,pcap,evidence,exploits}
touch ~/engagements/lab-baseline/{notes.md,writes.log,attck.md}
```

Inside the container these appear at `/engagements/lab-baseline/...` — outputs from `kali` commands land directly on host disk, surviving container teardown.

---

## Step 9 — (Optional) Add the AI Assistant

If you use [OpenClaw](https://docs.openclaw.ai) or another agentic AI:

```bash
cp -r ai-assistant/openclaw/* ~/
```

See [`docs/AI_ASSISTANT.md`](AI_ASSISTANT.md) for details.

---

## Day-2 Operations

### Update the image

```bash
cd ot-security-lab
git pull
docker build --pull -t kali-red:latest docker/kali-red/
docker rm -f kali-red
./scripts/start-kali-red.sh
```

### Reset to clean state

```bash
docker rm -f kali-red lab-target
docker compose -f docker/lab-target/compose.yml up -d
./scripts/start-kali-red.sh
```

### Stop the lab

```bash
docker stop kali-red lab-target
```

### Tear down completely (keeps `~/engagements/`)

```bash
docker rm -f kali-red lab-target
docker rmi kali-red:latest
```

---

## Troubleshooting

### "Permission denied while trying to connect to the docker API"

You haven't relogged after `usermod -aG docker`. Either log out fully and back in, or use `sg docker -c "..."` as a workaround.

### `nmap` raw socket errors inside the container

The container is missing `NET_RAW` / `NET_ADMIN`. Re-run `./scripts/start-kali-red.sh` — it sets both.

### Container can't reach the target

You're not using `--network host`, or the host itself can't reach the target. Test from the host first:

```bash
ping <target-ip>
nc -zv <target-ip> 502
```

### Wrapper says "container does not exist"

```bash
./scripts/start-kali-red.sh
```

### Build fails on a `git clone` step in the Dockerfile

Some upstream repos rot. The Dockerfile uses `|| true` so the build continues, but you'll lose those tools. See `docs/TOOLING.md` for alternatives.

---

## Next Steps

- Read [`docs/METHODOLOGY.md`](METHODOLOGY.md) for the engagement workflow
- Walk through [`playbooks/01-recon.md`](../playbooks/01-recon.md) for your first scan
- Review [`docs/SAFETY.md`](SAFETY.md) before any active testing
