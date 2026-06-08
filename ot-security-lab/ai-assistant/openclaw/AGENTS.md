# AGENTS.md — Conventions for AI Agents Working in This Lab

If you (the agent) are reading this, you are operating in an **OT/ICS security lab**. The rules below are non-negotiable.

## Hard Rules

1. **Read-only by default.** Any test that could change device state requires explicit authorization from the operator **in the current turn**. "Approval given earlier" is not approval for a new action.
2. **Stay in scope.** Confirm the target IP against `engagements/<name>/scope.md` before every active command.
3. **Snapshot before write.** Run `scripts/snapshot.py` (or equivalent), save under `engagements/<name>/baseline/`, *then* execute the write.
4. **Log everything.** Every command goes to `engagements/<name>/notes.md` with a UTC timestamp. Every write goes to `writes.log` *before* execution, with the restore command.
5. **One destructive test at a time.** Do not chain.
6. **Stop on uncertainty.** If you are unsure whether something is safe, ask the operator.

## Working Conventions

- Use the `kali` wrapper, not raw `docker exec`. It keeps invocation consistent.
- Save all `nmap` output with `-oA` (gives `.nmap`, `.gnmap`, `.xml`).
- Use UTC timestamps in logs (`date -u +%Y-%m-%dT%H:%M:%SZ`).
- Map each finding to a MITRE ATT&CK for ICS technique ID.
- Reference the playbooks (`playbooks/01-recon.md`, etc.) rather than inventing methodology.

## Files You Should Know About

| File | Purpose |
|---|---|
| `KALI.md` | The tool playbook — recipes and decision-tree |
| `docs/METHODOLOGY.md` | Phase-by-phase workflow |
| `docs/SAFETY.md` | Full rules of engagement |
| `engagements/<name>/scope.md` | What's authorized for this engagement |
| `engagements/<name>/notes.md` | Append-only narrative log |
| `engagements/<name>/writes.log` | Pre-flight log for every write |

## When You Don't Know What to Do

Default to:

1. Read the relevant playbook
2. Run a read-only command
3. Document what you found
4. Ask the operator for next-step direction

Do not improvise destructive tests.
