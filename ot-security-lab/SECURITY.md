# Security Policy

## Reporting a Vulnerability in This Repo

If you find a security issue **in this repository itself** (scripts, Dockerfile, documentation that could mislead a user into a dangerous action), please open a GitHub issue or contact the maintainer privately.

## Reporting a Vulnerability in an Upstream Tool

If, while using this lab, you discover a vulnerability in an upstream tool — pymodbus, nmap, Kali packages, etc. — **do not file it here**.

Report it to the upstream project through their disclosure process:
- pymodbus: https://github.com/pymodbus-dev/pymodbus/security/policy
- nmap: https://nmap.org/book/man-bugs.html
- Kali packages: https://www.kali.org/security/
- Other: check the project's `SECURITY.md` or their security contact

Follow responsible disclosure timelines.

## Reporting a Vulnerability in a Real Device

If you discover a vulnerability in a real industrial device or product:

1. Do not publish a PoC here.
2. Contact the vendor's product security team.
3. CISA accepts ICS vulnerability reports: https://www.cisa.gov/report
4. Consider coordinated disclosure through the vendor or via CERT/CC.

## Scope of This Lab

This lab is intended for:
- Educational use against the simulators it ships with
- Research against devices you own
- Authorized engagements against documented scopes

It is **not** intended to be used to attack production infrastructure or any system you don't own / have written authorization for.
