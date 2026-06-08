# Playbook 01 — Reconnaissance

**Goal:** Build an inventory of every live host on the lab subnet and identify which speak industrial protocols.

**Time:** 10-20 minutes for a /24

**Risk:** Very low. Read-only network activity.

---

## Prerequisites

- Engagement folder created (`scripts/new-engagement.sh <name>`)
- Scope confirmed in `scope.md`

## Steps

### 1. Host discovery

```bash
ENG=/engagements/<name>
SUBNET=192.168.1.0/24

kali nmap -sn $SUBNET -oA $ENG/recon/sweep
```

**Verify:** open `$ENG/recon/sweep.nmap`, confirm only expected lab IPs appear.

### 2. Full TCP per host

For each live host found:

```bash
TARGET=192.168.1.95
kali nmap -sS -sV -O -p- --reason -oA $ENG/recon/$TARGET-tcp $TARGET
```

### 3. ICS-protocol-specific port sweep

```bash
kali nmap -sS -p 102,502,1911,4840,20000,44818,47808 --open \
  -oA $ENG/recon/ics-ports $SUBNET
```

Common ICS ports:

| Port | Protocol | Vendor association |
|---|---|---|
| 102 | S7 / ISO-TSAP | Siemens |
| 502 | Modbus TCP | All vendors |
| 1911 | Niagara Fox | Tridium |
| 4840 | OPC UA | Modern middleware |
| 20000 | DNP3 | Power/utility |
| 44818 | EtherNet/IP | Rockwell/Allen-Bradley |
| 47808 | BACnet | Building automation |

### 4. Passive baseline capture

In a separate shell, capture 5 minutes of "normal" traffic for later comparison:

```bash
kali -c "tcpdump -i any -w $ENG/pcap/baseline-$(date +%Y%m%d-%H%M%S).pcap \
  'port 502 or port 102 or port 44818 or port 20000'"
```

Let it run while HMI/operators do normal things. Kill with Ctrl-C when done.

### 5. Document findings

Append to `$ENG/notes.md`:

```markdown
## Recon — <date>

Subnet sweep: <N> hosts up.

### Hosts of interest
- 192.168.1.95 — Modbus TCP (:502) open
- 192.168.1.20 — S7 (:102) open

### Suspicious / unexpected
- _(none)_
```

---

## Common Pitfalls

- **Too aggressive timing** — default `-T3` is fine for ICS. `-T4`/`-T5` can crash fragile devices.
- **Forgetting `-Pn`** — some PLCs don't reply to ICMP. If host discovery misses something you know is there, retry with `-Pn`.
- **Confusing recon with enumeration** — recon answers "what's there?". Enumeration (next playbook) answers "what is it?".

## MITRE ATT&CK for ICS

- [T0846 Remote System Discovery](https://attack.mitre.org/techniques/T0846/)
- [T0840 Network Connection Enumeration](https://attack.mitre.org/techniques/T0840/)

## Next

→ [Playbook 02 — Enumeration](02-enumeration.md)
