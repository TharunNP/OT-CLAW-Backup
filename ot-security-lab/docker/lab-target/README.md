# Lab Target — Pymodbus Simulator

A safe, configurable Modbus TCP server for practice.

## Why a simulator?

- Won't break under fuzzing
- Reset by restarting the container
- No physical process at risk
- Lets you focus on the protocol, not the process

## Start / Stop

```bash
docker compose up -d         # start
docker compose logs -f       # follow logs
docker compose down          # stop
docker compose restart       # restart
```

## Verify

```bash
nc -zv 127.0.0.1 502
nmap -p 502 --script modbus-discover 127.0.0.1
```

## Configuration

Edit `modbus-config.json` to change register/coil layouts, slave IDs, or device identification strings.

## When you need more

For deeper realism, switch to:

- **OpenPLC** — full software PLC supporting IEC 61131-3 logic + Modbus
- **GRFICS** — a complete virtual ICS testbed (chemical plant simulation)
- A **real PLC** on the lab subnet (Siemens LOGO! 8, Click PLC, etc.)
