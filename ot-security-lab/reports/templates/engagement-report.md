# Engagement Report — <NAME>

**Engagement ID:** <id>
**Dates:** YYYY-MM-DD → YYYY-MM-DD
**Author:** <name>
**Authorization:** see `scope.md`

---

## 1. Executive Summary

_One page. No jargon. Lead with the most important finding in plain language. Quantify impact where possible (downtime, safety, financial)._

---

## 2. Scope

**In scope:**
- _<ip / cidr>_

**Out of scope:**
- _<list>_

**What we tested:**
- _<phases run>_

**What we did not test:**
- _<phases skipped and why>_

---

## 3. Methodology

This engagement followed the methodology documented in [`docs/METHODOLOGY.md`](../../docs/METHODOLOGY.md), aligned to:

- PTES (Penetration Testing Execution Standard)
- SANS ICS Cyber Kill Chain
- MITRE ATT&CK for ICS (v13)

Phases executed:

1. ☑ Reconnaissance
2. ☑ Enumeration
3. ☑ Baseline snapshot
4. ☑ Active probing
5. ☐ Controlled process impact _(not authorized)_
6. ☑ Reporting

---

## 4. Findings Summary

| ID | Severity | Title | MITRE |
|---|---|---|---|
| F-01 | High | _<title>_ | Txxxx |
| F-02 | Medium | _<title>_ | Txxxx |

---

## 5. Findings

### F-01 — _<title>_

**Severity:** _<rating>_
**MITRE ATT&CK for ICS:** _<Txxxx>_
**Affected:** _<ip:port>_

**Description:**
_<what>_

**Evidence:**
- _<path/to/artifact>_

**Process impact:**
_<safety/availability/integrity in real-world terms>_

**Recommendations:**
1. _<compensating control, short-term>_
2. _<strategic fix, long-term>_
3. _<detection guidance>_

---

### F-02 — _<title>_

_(repeat structure)_

---

## 6. MITRE ATT&CK for ICS Mapping

See [`reports/templates/attck-mapping.md`](attck-mapping.md).

---

## 7. Recommendations — Prioritized

| Priority | Recommendation | Effort | Time horizon |
|---|---|---|---|
| 1 | _<thing>_ | Low | Days |
| 2 | _<thing>_ | Medium | Weeks |
| 3 | _<thing>_ | High | Months |

---

## 8. Appendices

- **A.** Raw nmap output — `recon/*.xml`
- **B.** Packet captures — `pcap/*.pcap`
- **C.** Scripts used — `exploits/`
- **D.** Baseline snapshots — `baseline/`
- **E.** Engagement log — `notes.md`

---

_Generated from `reports/templates/engagement-report.md`._
