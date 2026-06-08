# Playbook 02 — Enumeration

**Goal:** For each ICS device found in recon, identify vendor, model, firmware, and exposed services.

**Time:** 5-10 minutes per device

**Risk:** Low. Still read-only, but more chatty than recon.

---

## Modbus Devices

```bash
TARGET=192.168.1.95
ENG=/engagements/<name>

kali nmap -p 502 \
  --script modbus-discover \
  --script-args 'modbus-discover.aggressive=true' \
  -oN $ENG/enumeration/$TARGET-modbus.txt $TARGET
```

Records:
- Slave IDs that respond
- Device identification string (vendor, model, firmware)

## Siemens S7 (port 102)

```bash
kali nmap -p 102 --script s7-info -oN $ENG/enumeration/$TARGET-s7.txt $TARGET
```

Returns module type, serial, firmware. Cross-reference with [CISA advisories](https://www.cisa.gov/news-events/cybersecurity-advisories).

## EtherNet/IP (Rockwell, port 44818)

```bash
kali nmap -p 44818 --script enip-info -oN $ENG/enumeration/$TARGET-enip.txt $TARGET
```

## BACnet (building automation, port 47808)

```bash
kali nmap -p 47808 --script bacnet-info -oN $ENG/enumeration/$TARGET-bacnet.txt $TARGET
```

## Web Management Interface

Most PLCs ship with web admin. Check what's there:

```bash
kali nikto -h http://$TARGET -o $ENG/enumeration/$TARGET-nikto.txt
```

Default-credential check (use a small wordlist for ICS — see `playbooks/wordlists/`):

```bash
kali hydra -L users.txt -P passwords.txt $TARGET http-get /
```

## SNMP

Many PLCs leave SNMP enabled with default community strings:

```bash
for COMM in public private manager; do
  kali -c "snmpwalk -v2c -c $COMM $TARGET 2>&1 | head -20"
done
```

## CVE Cross-Reference

Once you have vendor + firmware:

```bash
kali searchsploit "<vendor> <model>"
kali searchsploit modbus
```

Also check:
- https://www.cisa.gov/news-events/cybersecurity-advisories
- https://nvd.nist.gov/

## Document

For each device, create `$ENG/enumeration/$TARGET.md`:

```markdown
# 192.168.1.95

## Identification
- Vendor: <from modbus-discover>
- Model: <from modbus-discover>
- Firmware: <from modbus-discover>
- Slave IDs responding: <list>

## Services
- 502/tcp Modbus TCP
- 80/tcp HTTP (web admin) - default credentials: <yes/no>
- 161/udp SNMP - community: <if any worked>

## Known vulnerabilities
- <CVE-YYYY-NNNNN> — <one-line description>

## Notes
- _<anything unusual>_
```

---

## MITRE ATT&CK for ICS

- [T0888 Remote System Information Discovery](https://attack.mitre.org/techniques/T0888/)
- [T0840 Network Connection Enumeration](https://attack.mitre.org/techniques/T0840/)

## Next

→ [Playbook 03 — Modbus Operations](03-modbus-ops.md)
