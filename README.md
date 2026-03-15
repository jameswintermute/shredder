# Shredder — NAS External Backup Disk Cleaner

**Version:** v1.7.0 — 2026-03-14
**Author:** James Wintermute
**License:** GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.html)
**Warranty:** This program comes with ABSOLUTELY NO WARRANTY.

---

## Overview

Shredder is a command-line utility designed for **Synology NAS environments (BusyBox-based)** to securely clean **external USB backup disks** between backup rotation cycles. It supports both safe, non-destructive filesystem wipes and full-device forensic shreds.

Typical installation path:
```
/volume1/shredder/shredder-v1.7.0/
```

Run as **root** for full device access.

---

## Features

- Interactive **menu-driven interface** — no arguments needed
- **Filesystem-preserving wipe** (default): clears all files then fills free space with random and zero passes; partition table intact and disk immediately reusable
- **Full device shred** (forensic mode): overwrites the entire device including partition table; configurable pass count + final zero pass
- **Live progress view** (option 3): auto-refreshing display showing phase, progress bar, bytes written, ETA, and elapsed time — press Ctrl+C to return to the menu at any time
- **Live 60s throughput benchmark** with real-time progress updates (`estimate.sh`)
- Estimate table covering 1-, 2-, and 3-pass full shred and filesystem wipe in a single run
- Safety guard refusing to operate on devices that look like system disks (`/dev/sda`, `sdb`, `md*`, `vda*`)
- Background operation — shredding runs detached; the menu remains usable
- Logs every action with timestamps and results under `logs/`
- Persistent **history CSV** (`logs/history.csv`) for audit or SIEM ingestion

---

## Directory Structure

```
shredder-v1.7.0/
├── bin/
│   ├── check-deps.sh        # Dependency checker
│   ├── estimate.sh          # 60s live write benchmark
│   └── shredder.sh          # Main menu and all logic
├── logs/                    # Per-run logs and history CSV
├── state/                   # Runtime state (PID, phase, progress file)
├── start-shredding.sh       # Thin launcher (resolves own path)
├── LICENSE
└── README.md
```

All paths — logs, state, progress file — are resolved **relative to the script's own location**, so the tool works correctly regardless of where it is installed or what the folder is named.

---

## Launching

```bash
sudo /volume1/shredder/shredder-v1.7.0/start-shredding.sh
```

The launcher resolves its own directory at runtime, so it works correctly when called from any path, including from cron.

---

## Menu Options

```
  1)  List USB disks
  2)  Start wipe / shred
  3)  Check progress
  4)  Show history
  5)  Check dependencies
  6)  Estimate shred time
  0)  Exit
```

---

## Live Progress View (option 3)

Selecting option 3 enters a **live auto-refreshing display** that updates every 5 seconds:

```
----------------------------------------------------
  SHREDDER — Progress Report
  Updated    : 2026-03-14 14:18:07  (refreshes every 5s)
----------------------------------------------------

  Operation  : Filesystem Wipe
  Device     : /dev/sdq   Seagate ExpansionHDD   4 TiB
  Started    : 2026-03-14 14:12:28
  Status     : RUNNING

  Phase      : Phase 2 of 3: random overwrite fill
  Progress   : [####................]  20%  (by fill-file size)
  Written    : 820 GiB of ~4 TiB
  ETA        : approx 3h 12m 44s remaining
  Elapsed    : 0h 47m 22s

  Log        : /volume1/shredder/shredder-v1.7.0/logs/fswipe-20260314-141228-sdq1.log
----------------------------------------------------

  Auto-refreshing every 5s — press Ctrl+C to return to menu
```

When the operation completes, the display updates one final time to show the result and duration, then waits for Enter before returning to the menu.

The progress file (`state/progress.txt`) is also readable directly — useful for remote monitoring:

```bash
watch -n5 cat /volume1/shredder/shredder-v1.7.0/state/progress.txt
```

---

## Estimate Feature (option 6)

Runs a real 60-second write benchmark on the selected mount, then prints a time estimate table:

```
  Measured write rate : 97 MB/s

  Mode                                    Estimated time
  ----------------------------------------------------
  Full device shred — 1-pass + zero       7h 14m
  Full device shred — 2-pass + zero       10h 51m
  Full device shred — 3-pass + zero       14h 28m
  Filesystem wipe (non-destructive)       7h 14m
```

The benchmark prints live progress to the terminal every 10 seconds while it runs.

---

## Shred Modes

### Quick Wipe (mode 1 — default)

The correct choice for backup disk rotation. Preserves the partition table. Two phases:

1. Delete all existing files and directories on the mount
2. Fill free space with zeros (`/dev/zero`) — runs at full USB disk speed

A 4 TiB disk at ~100 MB/s takes roughly 11 hours. The disk is ready to reuse immediately.

### Secure Wipe (mode 2)

Adds a random overwrite pass before the zero fill. **Use with caution on Synology NAS.**
`/dev/urandom` is CPU-bound on NAS hardware with no entropy acceleration — on a 4 TiB disk the random fill phase alone can take 1000+ hours. Only use this if you have a specific forensic requirement. The tool warns you before proceeding.

### Full Device Shred (mode 3 — forensic)

Operates on the whole block device. The mount is unmounted first. Passes:

1. N × random overwrite passes (configurable; default 2)
2. Final zero pass

The disk will require repartitioning and formatting before reuse.

---

## Risk & Safety

**This tool permanently destroys data.**

- Always verify the device path shown before typing YES.
- The confirmation prompt requires the exact string `YES` (uppercase) — anything else aborts.
- Shredder refuses to operate on `/dev/sda`, `/dev/sdb`, `/dev/md*`, or `/dev/vda*` in full-device mode, as these are typically system or internal disks on a Synology NAS.
- It is safe to use the menu while a shred is in progress — the background job is unaffected.

---

## Logs & History

Per-run logs are written to `logs/` with timestamped filenames:

```
logs/fswipe-20260314-141228-sdq1.log
logs/shred-20260314-141228-sdc.log
```

A running CSV summary is maintained at `logs/history.csv`:

```
timestamp,device,mode,passes,result,bytes,start_ts,end_ts,duration_s,logfile
```

The `duration_s` column makes it straightforward to compute statistics or ingest into a SIEM.

---

## Dependencies

Shredder uses only standard BusyBox / NAS utilities — no packages to install on a default Synology DSM:

| Command    | Purpose                          |
|------------|----------------------------------|
| `shred`    | Full-device overwrite            |
| `dd`       | Filesystem fill passes           |
| `mount`    | Detect USB mounts                |
| `umount`   | Unmount before device shred      |
| `awk`      | Parsing and formatting           |
| `sed`      | String manipulation              |
| `date`     | Timestamps                       |
| `kill`     | Process liveness check (POSIX)   |
| `sync`     | Flush writes to disk             |
| `df`       | Disk space queries               |
| `blockdev` | Precise disk size *(optional)*   |

Check availability with:

```bash
sudo sh /volume1/shredder/shredder-v1.7.0/bin/check-deps.sh
```

---

## Example Workflow

1. Plug in an external USB backup disk.
2. Run: `sudo /volume1/shredder/shredder-v1.7.0/start-shredding.sh`
3. **Option 1** — confirm the disk is detected and check its size and model.
4. **Option 6** — run the benchmark to estimate how long the wipe will take.
5. **Option 2** — select the disk and mode, confirm with `YES`.
6. **Option 3** — watch live progress; Ctrl+C returns to the menu without interrupting the shred.
7. When complete, the history is appended to `logs/history.csv`.

---

## Changelog

| Version | Date       | Summary                                                                  |
|---------|------------|--------------------------------------------------------------------------|
| v1.0.3  | 2025-11-11 | Initial release — basic menu, fs wipe, full device shred, estimate       |
| v1.1.0  | 2025-11-11 | Bug fixes; structured progress file; background monitor; estimate table  |
| v1.3.0  | 2026-03-14 | Live auto-refreshing progress view; self-relative paths; Ctrl+C to menu  |
| v1.4.0  | 2026-03-14 | Rate-based ETA from first sample; MB/s rate line; <1% bar on large disks |
| v1.5.0  | 2026-03-15 | Quick wipe (zero only, full speed) is now default; urandom pass is opt-in with CPU warning |
| v1.6.0  | 2026-03-15 | Cancel active operation (option 7); SIGTERM/SIGKILL sequence; partial-wipe warning in progress file |
| v1.7.0  | 2026-03-15 | Disk sizes now show one decimal place (4.6 TiB not 4 TiB) |

---

## Forensic Integrity Notes

- Uses `shred` and `dd` for low-level writes; no userspace buffering shortcuts.
- Random fill sourced from `/dev/urandom`.
- All operations append completion timestamps and exit codes to the per-run log.
- History CSV provides a chain-of-evidence record suitable for operational assurance.

---

© 2025–2026 James Wintermute
Released under GNU GPLv3 — https://www.gnu.org/licenses/gpl-3.0.html
