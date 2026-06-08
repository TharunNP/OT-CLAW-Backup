# Playbook 06 — Reporting

**Goal:** Turn engagement artifacts into a deliverable a stakeholder can act on.

---

## What Makes an OT Report Different

| IT report | OT report |
|---|---|
| Finds: "shell on the box" | Finds: "we could trip the emergency stop" |
| Risk in CIA terms | Risk in safety/availability/process terms |
| Patch as the fix | Patching may be a 12-month project; compensating controls matter |
| Audience: SOC, IT ops | Audience: process engineers, plant managers, safety officers |

Write for someone who knows pumps and PIDs, not someone who knows CVSS by heart.

---

## Structure

Use [`reports/templates/engagement-report.md`](../reports/templates/engagement-report.md) as a starting point.

1. **Cover** — engagement name, dates, scope, authorization reference
2. **Executive summary** — 1 page, no jargon, lead with business/safety impact
3. **Scope** — what was in, what was out, what we didn't get to
4. **Methodology** — phases, tools, frameworks used
5. **Findings** — one section per finding (see below)
6. **MITRE ATT&CK for ICS mapping table** — at-a-glance view
7. **Recommendations** — prioritized, concrete
8. **Appendices** — raw output, scripts, pcaps

## Anatomy of a Finding

```markdown
### F-03 — Unauthenticated Modbus writes accepted on slave 1

**Severity:** High
**MITRE ATT&CK for ICS:** T0836 Modify Parameter, T0855 Unauthorized Command Message
**Affected:** 192.168.1.95:502

**Description:**
The Modbus TCP server at 192.168.1.95 accepts coil and holding-register writes from any
network source on the lab subnet without authentication. This is inherent to the Modbus
TCP protocol but is amplified here by the lack of network segmentation between the
control LAN and the engineering workstation VLAN.

**Evidence:**
- Snapshot before write: `baseline/192.168.1.95-20260607T180000Z.json`
- Write command: `writes.log:14`
- Snapshot after write: `baseline/192.168.1.95-20260607T180015Z.json`
- Diff: coil 0 changed from 0 → 1

**Process impact (lab):**
In a real deployment, coil 0 controls pump start/stop. An attacker could start the
pump unexpectedly, causing dry-run damage.

**Recommendations:**
1. **Compensating control (90 days):** Deploy a Modbus-aware firewall (e.g. Bayshore,
   Tofino) between the control LAN and any other network. Restrict source IPs allowed
   to issue function codes 5, 6, 15, 16.
2. **Strategic (12 months):** Migrate to Modbus Security (RFC-equivalent specification),
   OPC UA with certificate auth, or a vendor-specific authenticated protocol.
3. **Detection:** Log all Modbus writes at the firewall; alert on writes from non-HMI
   source IPs.
```

## MITRE Mapping Table

In `attck.md`:

```markdown
| Finding | Technique | Tactic |
|---|---|---|
| F-01 | T0846 Remote System Discovery | TA0100 Reconnaissance |
| F-02 | T0888 Remote System Information Discovery | TA0102 Discovery |
| F-03 | T0836 Modify Parameter | TA0106 Impair Process Control |
| F-04 | T0814 Denial of Service | TA0107 Inhibit Response Function |
| F-05 | T0830 Adversary-in-the-Middle | TA0109 Lateral Movement |
```

## Severity Ratings

Use process/safety terms:

| Rating | Meaning |
|---|---|
| Critical | Direct safety impact possible (injury, environmental release) |
| High | Process disruption possible (downtime, product loss) |
| Medium | Information disclosure or precondition for higher-impact attacks |
| Low | Limited operational impact |
| Informational | Best-practice observation, no exploitable issue |

## Scrubbing Before Delivery

Before sharing or publishing the report:

- [ ] Remove credentials (even rotated ones)
- [ ] Redact serial numbers in screenshots
- [ ] Confirm IPs/hostnames don't leak production topology if this is a research report
- [ ] Verify embedded captures are sanitized

## Templates

- [`reports/templates/engagement-report.md`](../reports/templates/engagement-report.md)
- [`reports/templates/attck-mapping.md`](../reports/templates/attck-mapping.md)
