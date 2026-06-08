#!/usr/bin/env python3
"""
snapshot.py — capture a Modbus device's current state.

Reads coils, discrete inputs, holding registers, and input registers
across a configurable address range and writes a timestamped JSON
snapshot. Use BEFORE any write test so you can prove what changed
and restore the original values.

Usage:
    snapshot.py --target 192.168.1.95 --out baseline.json
    snapshot.py --target 192.168.1.95 --slave 1 --count 100 --out baseline.json
"""

import argparse
import json
import sys
from datetime import datetime, timezone

try:
    from pymodbus.client import ModbusTcpClient
except ImportError:
    print("pymodbus not installed. Run inside kali-red or 'pip install pymodbus'.", file=sys.stderr)
    sys.exit(1)


def safe_read(fn, *args, **kwargs):
    """Run a pymodbus read; return list-of-values or None on failure."""
    try:
        rr = fn(*args, **kwargs)
    except Exception as e:
        return {"error": str(e)}
    if rr is None or rr.isError():
        return {"error": str(rr)}
    if hasattr(rr, "bits"):
        return rr.bits
    if hasattr(rr, "registers"):
        return rr.registers
    return {"error": "unknown response shape"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--port", type=int, default=502)
    ap.add_argument("--slave", type=int, default=1)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    c = ModbusTcpClient(args.target, port=args.port)
    if not c.connect():
        print(f"FAIL: could not connect to {args.target}:{args.port}", file=sys.stderr)
        sys.exit(2)

    snap = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "target": args.target,
        "port": args.port,
        "slave": args.slave,
        "start": args.start,
        "count": args.count,
        "coils": safe_read(c.read_coils, args.start, args.count, slave=args.slave),
        "discrete_inputs": safe_read(c.read_discrete_inputs, args.start, args.count, slave=args.slave),
        "holding_registers": safe_read(c.read_holding_registers, args.start, args.count, slave=args.slave),
        "input_registers": safe_read(c.read_input_registers, args.start, args.count, slave=args.slave),
    }

    c.close()

    with open(args.out, "w") as f:
        json.dump(snap, f, indent=2, default=str)

    print(f"[+] Snapshot written: {args.out}")


if __name__ == "__main__":
    main()
