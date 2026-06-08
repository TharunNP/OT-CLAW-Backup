# Contributing

This is a personal lab repository, but contributions, corrections, and improvements are welcome.

## Ground Rules

1. **No live exploit code against real products without coordinated disclosure context.**
   Generic protocol weaknesses (Modbus has no auth, etc.) are fine. CVE-specific exploits should reference public advisories and disclosure status.
2. **No engagement artifacts.** Never commit `engagements/` content, captures, or anything containing real credentials, real IPs, or real device serials.
3. **Lab-only orientation.** Anything you contribute should reinforce the "lab-only" framing, not undermine it.

## How to Contribute

### Documentation improvements
PRs welcome for typos, clarifications, or expanded explanations.

### New playbooks
Add to `playbooks/` following the existing format:
- Goal, Time, Risk header
- Prerequisites
- Steps with verifications
- MITRE mapping
- Pointer to the next playbook

### New tools in `kali-red`
Add the apt/pip package to `docker/kali-red/Dockerfile`. Briefly justify in the PR why it earns its place — the image is already large.

### New targets
For new simulator targets (OpenPLC config, GRFICS scenarios, etc.), add under `docker/<target-name>/` with a `compose.yml` and `README.md`.

## Style

- Markdown over heavy formatting
- Mermaid for diagrams (renders in GitHub)
- Concrete commands over abstract explanations
- Plain text outputs over screenshots where possible

## Reporting Issues with Upstream Tools

If you discover a vulnerability in pymodbus, OpenPLC, or any other upstream component while using this lab:

1. **Do not file it as an issue here.**
2. Report it to the vendor through their disclosure process.
3. Follow coordinated disclosure timelines.

We'll happily reference public advisories once they're out.
