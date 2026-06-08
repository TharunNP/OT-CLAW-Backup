# `kali-red` Container

The attacker rig. A Kali Linux derivative pre-loaded with the OT/ICS security toolkit.

## Build

```bash
docker build -t kali-red:latest .
```

~5-15 minutes depending on bandwidth. ~5 GB on disk.

## Run

Use [`scripts/start-kali-red.sh`](../../scripts/start-kali-red.sh) from the repo root — it sets all the correct flags.

## What's inside

See [`docs/TOOLING.md`](../../docs/TOOLING.md) for the full inventory and use cases.

## Why these flags

| Flag | Reason |
|---|---|
| `--network host` | Direct access to the lab subnet (needed for raw scans and MITM) |
| `--cap-add=NET_RAW` | Raw socket creation for nmap SYN, hping, scapy |
| `--cap-add=NET_ADMIN` | Interface manipulation for arpspoof, ettercap |
| `-v ~/engagements:/engagements` | Persist artifacts to host disk |
| `--restart unless-stopped` | Container survives host reboots |
