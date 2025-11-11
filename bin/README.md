# Shredder — NAS External Backup Disk Cleaner

**Shredder** is a lightweight shell utility for securely erasing external USB backup drives attached to a Synology NAS.  
It is designed for **BusyBox-based DSM systems** and runs directly from a directory such as:

```
/volume1/shredder
```

Run as the **root user** to allow direct access to block devices.

---

## ⚠️ WARNING — DATA DESTRUCTION TOOL

Shredder performs irreversible disk wipes using the Linux `shred` utility.  
Once started, **all data on the target disk is permanently destroyed** — including the filesystem, partition table, and any residual metadata.

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
│   ├── shredder.sh        # main menu (interactive)
│   ├── check-deps.sh      # dependency checker
│   └── start-shredding.sh # launcher (recommended entry point)
├── logs/
│   ├── history.csv        # shred history (SIEM-friendly)
│   └── shred-*.log        # individual shred runs
├── state/
│   └── current.*          # runtime state tracking
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

3. Run the launcher:

   ```bash
   ./bin/start-shredding.sh
   ```

4. From the menu, choose:
   - **1** — List detected external USB disks  
   - **2** — Start a new shred  
   - **3** — Monitor current shred progress  
   - **4** — View shred history  
   - **5** — Check dependencies  
   - **0** — Exit

---

## 🧠 How It Works

- The script enumerates external disks mounted under `/volumeUSB`.
- It safely unmounts the target and wipes the **whole device** (not just the partition).
- Progress and detailed logs are written to `logs/shred-*.log`.
- A structured `logs/history.csv` file records each shred event with timestamp, device, passes, and result — suitable for SIEM ingestion.

---

## 🔒 Safety Features

- Rejects likely system disks (e.g., `/dev/sda`, `/dev/sdb`, `/dev/md*`).
- Requires manual confirmation before shredding.
- Runs one shred job at a time.
- Keeps all activity logged and timestamped.

---

## 🧩 Launcher Script

The `start-shredding.sh` launcher provides a simple entry point with:
- Dependency check (via `check-deps.sh`)
- Warning banner
- Launch of the interactive `shredder.sh` menu

This avoids confusion with the Hasher project’s `launcher.sh` and makes its destructive purpose clear.

---

## 🪪 License

Copyright (C) 2025 James Wintermute  
Licensed under **GNU GPLv3**  
<https://www.gnu.org/licenses/>

This program comes with **ABSOLUTELY NO WARRANTY.**
