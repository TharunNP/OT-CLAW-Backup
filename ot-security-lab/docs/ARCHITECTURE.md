# Architecture

This document describes the design of the OT security lab — what runs where, how the pieces talk to each other, and the security boundaries that keep lab activity from leaking out.

## Design Principles

1. **Containment over capability.** Every tool that exists in the lab should be containable. The attacker rig is a container precisely so it can be torn down and rebuilt deterministically.
2. **Realistic protocols, safe targets.** Use real industrial protocol stacks (pymodbus, OpenPLC, etc.), not toy mockups — but always against simulators, never against equipment you can't afford to lose.
3. **Reproducibility.** Every component is defined by a `Dockerfile`, a `compose.yml`, or a versioned script. No "works on my machine" steps.
4. **Audit by default.** Every command, every capture, every state-change is written to disk under `engagements/`.
5. **Network isolation.** The lab subnet is air-gapped or at minimum VLAN-segmented from production.

---

## High-Level Topology

```mermaid
flowchart TB
    subgraph EXT["🌐 External World"]
        INET["Internet / Home Network"]
    end

    subgraph LAB["🔒 Isolated Lab Network (e.g. 192.168.1.0/24)"]
        subgraph HOST["🖥️ Lab Host Machine"]
            subgraph DCK["🐳 Docker Engine"]
                KR["kali-red<br/>━━━━━━━━━━<br/>NET_RAW + NET_ADMIN<br/>host network<br/>/engagements mount"]
                SIM["pymodbus-simulator<br/>━━━━━━━━━━<br/>:502"]
            end
            FS[("📁 /engagements<br/>persistent artifacts")]
        end

        PLC["🏭 Real PLC (optional)<br/>e.g. Siemens S7-1200<br/>:102, :502"]
        HMI["🖥️ HMI / SCADA<br/>(optional)"]

        KR -.attack traffic.-> SIM
        KR -.attack traffic.-> PLC
        HMI -.normal traffic.-> SIM
        HMI -.normal traffic.-> PLC
    end

    OPERATOR["👤 Operator"] -->|SSH / local| HOST
    AI["🤖 AI Agent (optional)<br/>e.g. OpenClaw"] -.controls.-> HOST

    INET -. ❌ NO ROUTE .- LAB

    classDef target fill:#ffe4e1,stroke:#c0392b
    classDef attacker fill:#d4edda,stroke:#27ae60
    classDef host fill:#fff3cd,stroke:#f39c12
    class SIM,PLC,HMI target
    class KR attacker
    class HOST,DCK,FS host
```

**Key boundaries:**

- 🛑 **Lab ↔ Internet:** no route. Either fully air-gapped or strict egress firewall rules.
- 🐳 **Container ↔ Host:** the `kali-red` container runs with `--network host`. This is a deliberate trade-off — it gives us real lab-subnet access for raw scans and MITM, but means container processes share the host's network namespace. **Run the lab host only on the lab network**.
- 📁 **Container ↔ Filesystem:** only `/engagements` is mounted. The container has no other write paths to the host.

---

## The Attacker Container — `kali-red`

```mermaid
flowchart LR
    subgraph IMG["🐳 kali-red image"]
        direction TB
        BASE["kali:latest base"]
        APT["apt-installed:<br/>nmap, masscan, hping3<br/>tcpdump, tshark<br/>metasploit-framework<br/>ettercap, bettercap<br/>arpspoof, tcpreplay<br/>hydra, nikto, sqlmap<br/>searchsploit, snmpwalk"]
        PIP["pip-installed:<br/>pymodbus, pysnmp<br/>scapy, cpppo<br/>opcua, python-snap7<br/>boofuzz"]
        OPT["/opt/ specialized:<br/>isf (Industrial Exploitation Framework)<br/>plcscan<br/>ICSSecurityScripts"]
        BASE --> APT --> PIP --> OPT
    end

    subgraph RUN["▶️ Runtime"]
        direction TB
        NET["--network host"]
        CAPS["--cap-add NET_RAW<br/>--cap-add NET_ADMIN"]
        VOL["-v ~/engagements:/engagements"]
        RESTART["--restart unless-stopped"]
    end

    IMG --> RUN

    classDef img fill:#e8f4f8,stroke:#2980b9
    classDef run fill:#f4e8f8,stroke:#8e44ad
    class IMG,BASE,APT,PIP,OPT img
    class RUN,NET,CAPS,VOL,RESTART run
```

### Why these capabilities?

| Capability | What it unlocks | Why we need it |
|---|---|---|
| `NET_RAW` | Raw socket creation | nmap SYN scans, hping3, scapy packet crafting, NSE raw-packet scripts |
| `NET_ADMIN` | Interface manipulation | arpspoof, ettercap MITM, custom routing for transparent proxies |
| `--network host` | Direct host network namespace | Reaching the lab subnet without container NAT overhead; required for MITM and broadcast discovery |

### Why these protocol libraries?

| Library | Protocol | Used For |
|---|---|---|
| `pymodbus` | Modbus TCP/RTU | Reading/writing PLC registers and coils |
| `python-snap7` | Siemens S7 | Talking to S7-300/400/1200/1500 PLCs |
| `cpppo` | EtherNet/IP, CIP | Rockwell / Allen-Bradley devices |
| `opcua` | OPC UA | Modern industrial middleware |
| `pysnmp` | SNMP | Many PLCs expose management via SNMP |
| `scapy` | Anything you can craft | Protocol fuzzing, custom packet generation |
| `boofuzz` | Generic fuzzing | Function-code fuzzing on industrial protocols |

---

## The Target Side

### Default target: Pymodbus Simulator

```mermaid
flowchart TB
    subgraph CONTAINER["🐳 pymodbus-simulator container"]
        DAEMON["pymodbus.server<br/>listening :502"]
        STORE["Data store:<br/>holding registers<br/>input registers<br/>coils<br/>discrete inputs"]
        SLAVES["Slave IDs 1..247<br/>(configurable)"]
        DAEMON --- STORE
        DAEMON --- SLAVES
    end
    ATTACKER["kali-red"] -->|Modbus TCP| DAEMON
```

The pymodbus simulator is the **default safe target**. It is a high-fidelity Modbus TCP server with configurable register maps, identification strings, and slave IDs. It will not break, will not contaminate any physical process, and can be restored from a config file in seconds.

### Optional: Real PLC

For more realistic engagements, add a real low-cost PLC to the lab subnet:

- **Siemens LOGO! 8** — cheap, Ethernet, S7 protocol
- **Click PLC (AutomationDirect)** — supports Modbus TCP
- **OpenPLC** — software PLC runtime, supports IEC 61131-3 logic + Modbus

⚠️ **A real PLC can still be damaged by misuse.** Keep backups of the program; document every test.

---

## Network Topology Options

### Option A — Single isolated subnet (recommended for getting started)

```mermaid
flowchart LR
    HOST["Lab Host<br/>192.168.1.10"] --- SWITCH(["🔌 L2 Switch<br/>(or virtual)"])
    SWITCH --- SIM["pymodbus sim<br/>192.168.1.95<br/>(or on host)"]
    SWITCH --- PLC["PLC<br/>192.168.1.20"]
    SWITCH --- HMI["HMI<br/>192.168.1.30"]
    HOST -.no route.-x INET["🌐 Internet"]
```

### Option B — VLAN-segmented (if sharing physical infrastructure)

```mermaid
flowchart LR
    subgraph PROD["🏠 Home/Production VLAN"]
        LAPTOP["Workstation"]
    end
    subgraph LAB_VLAN["🔒 Lab VLAN (192.168.1.0/24)"]
        HOST["Lab Host"]
        PLC["PLC"]
        SIM["Simulator"]
    end
    LAPTOP -.SSH only.-> HOST
    PROD ---x|firewall blocks all<br/>except SSH| LAB_VLAN
```

### Option C — Fully virtualized (cheapest entry)

Everything on one hypervisor (Proxmox, VMware Workstation, etc.):

```mermaid
flowchart TB
    subgraph HV["🖥️ Hypervisor"]
        subgraph LAB_NET["Virtual switch — isolated"]
            HOST_VM["Lab Host VM<br/>(runs kali-red + sim)"]
            PLC_VM["OpenPLC VM"]
            HMI_VM["ScadaBR VM"]
        end
    end
```

---

## Data Flow — Anatomy of an Engagement

```mermaid
sequenceDiagram
    participant OP as 👤 Operator
    participant KR as 🐳 kali-red
    participant TGT as 🎯 Target
    participant FS as 📁 /engagements

    Note over OP,FS: 1. Recon
    OP->>KR: kali nmap -sn 192.168.1.0/24
    KR->>TGT: ICMP/ARP sweep
    TGT-->>KR: live hosts
    KR->>FS: write recon/sweep.{nmap,xml,gnmap}

    Note over OP,FS: 2. Enumeration
    OP->>KR: kali nmap --script modbus-discover ...
    KR->>TGT: Modbus FC 17 (Report Slave ID), FC 43/14 (Read Device ID)
    TGT-->>KR: vendor, model, firmware
    KR->>FS: write enumeration/<host>.md

    Note over OP,FS: 3. Baseline snapshot (before any writes!)
    OP->>KR: kali python3 snapshot.py
    KR->>TGT: read coils, holding regs, input regs
    TGT-->>KR: register/coil values
    KR->>FS: write baseline/<host>-<timestamp>.json

    Note over OP,FS: 4. Active probing / exploitation
    OP->>KR: (test action)
    KR->>TGT: protocol-specific request
    TGT-->>KR: response
    KR->>FS: append writes.log + notes.md

    Note over OP,FS: 5. Reporting
    OP->>FS: render REPORT.md from templates
```

---

## Security Model

### What this lab protects against

- ✅ Attacks leaking from the container to the host filesystem (only `/engagements` is mounted)
- ✅ Accidental targeting of internet hosts (no internet route from the lab subnet, if you set it up correctly)
- ✅ Container drift (everything is defined in code; rebuild from `Dockerfile`)
- ✅ Lost work (everything written under `/engagements` is on host disk)

### What this lab does **not** protect against

- ❌ A determined attacker with host access — the container runs with `NET_RAW` + `NET_ADMIN` and host network. Treat the host as compromised-equivalent if you ever expose it.
- ❌ Misconfiguration that puts the host on a production network — that is your responsibility, not the lab's.
- ❌ Mistakes — write operations against any device are real. Use the baseline + log pattern.

### Threat model assumptions

| Assumption | Why |
|---|---|
| The lab host is dedicated to lab use | Otherwise the host-network container could see production traffic |
| The lab subnet has no route to production | The container can scan anything reachable on its network |
| The operator has authorization to test everything reachable | This is your legal/ethical responsibility |
| Only trusted operators have host access | The attacker rig is privileged by design |

---

## Component Versions

| Component | Tested Version | Notes |
|---|---|---|
| Host OS | Ubuntu 22.04 / 24.04 | Any modern Linux with Docker should work |
| Docker Engine | 24.x+ | BuildKit recommended |
| Kali base image | `kali:latest` (rolling) | Pinned tag possible for reproducibility |
| pymodbus simulator | 3.13+ | |
| OpenPLC (optional) | v3 | Software PLC alternative |

---

## See Also

- [`SETUP.md`](SETUP.md) — replication steps
- [`METHODOLOGY.md`](METHODOLOGY.md) — how to actually use this
- [`SAFETY.md`](SAFETY.md) — rules of engagement
- [`TOOLING.md`](TOOLING.md) — what each tool is for
