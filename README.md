# Shredder — NAS External Backup Disk Cleaner

**Version:** v1.0.1 — 2025-11-11  
**Author:** James Wintermute  
**License:** GNU GPLv3  
**Warranty:** This program comes with ABSOLUTELY NO WARRANTY.

---

## 🧩 Overview

**Shredder** is a lightweight shell utility for securely erasing external USB backup drives attached to a Synology NAS.  
It is designed for **BusyBox-based DSM systems** and runs directly from a directory such as:

```
/volume1/shredder
```

Run as the **root user** to allow direct access to block devices.

Shredder offers two secure cleaning modes:

1. **Filesystem-preserving wipe (default)** — securely overwrites all file data and free space, but keeps the partition table and filesystem structure.  
2. **Full-device shred (forensic)** — overwrites the entire disk, destroying the filesystem and partition table completely.

---

## ⚠️ WARNING — DATA DESTRUCTION TOOL

Both modes are **irreversible**. Once a wipe or shred is started, **all data on the selected disk will be permanently destroyed**.

> **Use extreme care.**  
> Verify that you have complete, validated backups before proceeding.  
> Always double-check which `/dev/sdX` device you are selecting.

This program comes with **ABSOLUTELY NO WARRANTY.**  
See the included GNU GPLv3 license for details.

---

## 📂 Project Layout

```
shredder/
├── bin/
│   ├── shredder.sh          # main interactive menu
│   ├── check-deps.sh        # dependency checker
│   └── start-shredding.sh   # launcher (recommended entry point)
├── logs/
│   ├── history.csv          # shred history (SIEM-friendly)
│   └── shred-*.log          # individual shred/wipe logs
├── state/
│   └── current.*            # runtime state tracking
├── LICENSE
└── README.md
```

---

## 🚀 Quick Start

1. Copy the project to your NAS (e.g. `/volume1/shredder`).
2. SSH into your NAS and switch to root:

   ```bash
   sudo -i
   cd /volume1/shredder
   chmod +x bin/*.sh
   ```

3. Launch Shredder safely using:

   ```bash
   ./bin/start-shredding.sh
   ```

4. From the menu, choose:
   - **1** — List detected external USB disks  
   - **2** — Start a new wipe/shred  
   - **3** — Check current progress  
   - **4** — View shred history  
   - **5** — Check dependencies  
   - **0** — Exit

---

## 🧠 Modes Explained

### 1️⃣ Filesystem-Preserving Wipe (Default)

- Deletes all files and fills remaining free space with random data, then zeroes it.  
- **Preserves** the filesystem and partition table.  
- Ideal for **rotating backup disks** where you want the drive ready for reuse immediately after wiping.

**Command example:**
```bash
rm -rf /volumeUSB1/usbshare/*
dd if=/dev/urandom of=/volumeUSB1/usbshare/fill bs=1M
rm fill
dd if=/dev/zero of=/volumeUSB1/usbshare/fill bs=1M
rm fill
```

✅ Safe  
✅ Fast  
⚠️ Slight metadata remnants may remain (inode table, journal) — not suitable for forensic-level cleaning.

---

### 2️⃣ Full-Device Shred (Forensic)

- Unmounts the drive and overwrites the **entire device** (e.g. `/dev/sdq`).  
- Destroys all partitions, metadata, and filesystem information.  
- After completion, the drive must be re-partitioned or formatted before reuse.

**Command example:**
```bash
shred -v -n 2 -z /dev/sdq
```

✅ Forensic-grade  
⚠️ Requires reformatting after completion

---

## 🧩 Launcher Script

The launcher (`start-shredding.sh`) provides:
- A **warning banner** before use
- An automatic **dependency check**
- Launch of the main interactive menu (`shredder.sh`)
- Clear version/date banner (`v1.0.1 — 2025-11-11`)

This avoids confusion with other NAS tools like *Hasher* and prevents accidental data destruction.

---

## 📊 Logging & SIEM Integration

All activity is logged in:

```
/volume1/shredder/logs/
```

- `shred-*.log` or `fswipe-*.log` — full output of each run
- `history.csv` — append-only record with:
  ```
  timestamp,device,mode,passes,result,bytes,start_ts,end_ts,logfile
  ```

Example entry:
```
2025-11-11T14:05:30+00:00,/dev/sdq,fs-wipe,0,success,0,1731330300,1731330600,/volume1/shredder/logs/fswipe-20251111-1405-sdq.log
```

---

## 🔒 Safety Features

- Refuses to shred suspected system disks (`/dev/sda`, `/dev/sdb`, `/dev/md*`, etc.)
- Requires explicit `YES` confirmation before destructive operations
- Supports one active shred/wipe at a time
- Logs everything with timestamps for forensic traceability
- Preserves last operation state for recovery

---

## 🧰 Dependency Check

You can verify required commands with:

```bash
./bin/check-deps.sh
```

Typical dependencies:
- `shred`, `mount`, `umount`, `awk`, `sed`, `date`, `ps`, `dd`, `sync`

---

## 🪪 License

Copyright (C) 2025 James Wintermute  
Licensed under **GNU GPLv3**  
<https://www.gnu.org/licenses/>

This program comes with **ABSOLUTELY NO WARRANTY.**
