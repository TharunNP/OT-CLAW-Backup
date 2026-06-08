#!/usr/bin/env bash
# new-engagement.sh — scaffold a fresh engagement folder.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <engagement-name>" >&2
  exit 1
fi

NAME="$1"
ROOT="${ENGAGEMENTS_DIR:-$HOME/engagements}/$NAME"

if [ -e "$ROOT" ]; then
  echo "Already exists: $ROOT" >&2
  exit 1
fi

mkdir -p "$ROOT"/{recon,enumeration,baseline,pcap,exploits,evidence}

cat > "$ROOT/scope.md" <<EOF
# Scope — $NAME

**Authorized by:** $(whoami)
**Date:** $(date -u +%Y-%m-%d)
**Lab description:** _<one sentence>_

## In scope
- _<ip / cidr>_

## Out of scope
- Everything else

## Authorized actions
- [x] Recon
- [x] Enumeration
- [x] Read-only protocol ops
- [ ] Writes — per-test approval required
- [ ] DoS — per-test approval required
- [ ] MITM — per-test approval required

## Authorized hours
_<e.g. anytime>_

## Stop conditions
- Any device behavior I don't understand
- Any test affecting devices outside this scope
EOF

cat > "$ROOT/notes.md" <<EOF
# Engagement Notes — $NAME

Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Timeline
EOF

: > "$ROOT/writes.log"
: > "$ROOT/attck.md"

echo "[+] Scaffolded: $ROOT"
echo "    Fill out scope.md before running anything active."
