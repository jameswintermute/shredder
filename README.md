# Shredder — NAS External Backup Disk Cleaner

**Version:** v1.0.3 — 2025-11-11  
**Author:** James Wintermute  
**License:** GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.html)  
**Warranty:** This program comes with ABSOLUTELY NO WARRANTY.

---

## 🧩 Overview

Shredder is a command-line utility designed for **Synology NAS environments (BusyBox-based)** to securely clean **external USB backup disks** between backup cycles.  
It supports both safe, non-destructive filesystem wipes and full-device forensic shreds.

Typical installation path:
```
/volume1/shredder
```

Run as **root** for full access to external devices.

---

## ⚙️ Features

- Interactive **menu-driven launcher**
- **Filesystem-preserving wipe** (default): securely overwrites all file data and free space while preserving the partition table
- **Full device shred** (forensic mode): completely overwrites the disk including partition table (requires re-partitioning)
- **Live 60s throughput benchmark** via `estimate.sh`
- Automatic **dependency check** on startup
- Logs every action with timestamps and results under `/logs`
- Keeps a persistent **history CSV** for SIEM or audit ingestion

---

## 🧮 Estimate Feature (v1.0.3)

The **Estimate** option now runs a real 60-second write test to determine actual sustained write speed.

### How it works
- Writes temporary 100 MiB chunks to the selected mount for ~60 s.
- Measures true MB/s throughput.
- Deletes the temporary test file afterward.
- Uses the result to estimate how long a **2-pass + zero** shred would take.

If the benchmark cannot run, it falls back to **120 MB/s** assumed speed.

### Typical output
```
Running live 60s speed test on /volumeUSB1/usbshare ...
Measured rate: 97 MB/s
Estimated shred time (2-pass + zero): ~11h 40m
Planning window: between 9h and 13h
```

---

## 🧰 Directory Structure

```
/volume1/shredder/
├── bin/
│   ├── check-deps.sh        # Dependency checker
│   ├── estimate.sh          # 60s live speed test
│   └── shredder.sh          # Main interactive menu
├── logs/                    # Execution logs and CSV history
├── state/                   # PID and session tracking
├── start-shredding.sh       # Root launcher
├── LICENSE
└── README.md
```

---

## 🚀 Launching

From any path:
```bash
sudo /volume1/shredder/start-shredding.sh
```

The launcher automatically:
- Resolves its own directory (even when run from `/root` or cron)
- Performs dependency check
- Starts the main interactive menu

---

## 🧭 Menu Options

```
1) Check external USB disks
2) Start a new wipe/shred
3) Check current progress
4) Show history
5) Check dependencies
6) Shred estimate — calculate approx. time
0) Exit
```

---

## ⚠️ Risk & Safety

**This tool permanently destroys data.**

- Always double-check device paths (e.g., `/dev/sdq1`) before confirming.
- The default mode ("Filesystem-preserving wipe") **keeps the partition table** and is safe for reusing disks in a rotation.
- The full-device mode **erases everything**, including partition and filesystem structure — use with extreme care.
- It is strongly recommended to **unmount** the target volume manually or let Shredder do it when prompted.

---

## 🧾 Logs & History

All actions are recorded to:
```
/volume1/shredder/logs/
```

A CSV summary (`history.csv`) maintains an audit-friendly record:
```
timestamp,device,mode,passes,result,bytes,start_ts,end_ts,logfile
```

This data can be ingested into SIEM or forensic log systems for traceability.

---

## 🧩 Dependencies

Shredder relies on standard BusyBox or NAS utilities:
- `dd`
- `shred`
- `umount`
- `blockdev`
- `sync`
- `ps`
- `mount`

Check these automatically with:
```bash
sudo sh /volume1/shredder/bin/check-deps.sh
```

---

## ✅ Example Workflow

1. Plug in an external USB backup disk.
2. Run:
   ```bash
   sudo /volume1/shredder/start-shredding.sh
   ```
3. Choose option 1 to verify your USB disk is detected.
4. Choose option 2 to start a wipe or shred.
5. Option 6 can estimate total time required.
6. Monitor progress (option 3) or review logs afterward.

---

## 🔒 Forensic Integrity Notes

- Uses `dd` and `shred` for low-level writes.
- Supports random fill and zero fill operations.
- Automatically appends completion timestamps and results.
- Maintains a chain-of-evidence log for operational assurance.

---

© 2025 James Wintermute  
Released under GNU GPLv3 — https://www.gnu.org/licenses/gpl-3.0.html
