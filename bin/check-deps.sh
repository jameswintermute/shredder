#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# bin/check-deps.sh — dependency checker
# v1.7.0

echo "Shredder dependency check"
echo "----------------------------------------------------"

MISSING=0

# check_cmd <command> <purpose>
check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        printf "  [OK]    %-12s %s\n" "$1" "$2"
    else
        printf "  [MISS]  %-12s %s\n" "$1" "$2"
        MISSING=1
    fi
}

# Required
check_cmd shred   "full-device overwrite"
check_cmd dd      "filesystem fill passes"
check_cmd mount   "detect USB mounts"
check_cmd umount  "unmount before device shred"
check_cmd awk     "output parsing"
check_cmd sed     "string manipulation"
check_cmd date    "timestamps"
check_cmd ps      "process listing (fallback)"
check_cmd kill    "process liveness check"
check_cmd sync    "flush writes to disk"
check_cmd df      "disk space queries"

echo "----------------------------------------------------"

# Optional but useful
if command -v blockdev >/dev/null 2>&1; then
    printf "  [OK]    %-12s %s\n" "blockdev" "precise disk size (optional)"
else
    printf "  [WARN]  %-12s %s\n" "blockdev" "not found — size estimated from /sys (optional)"
fi

echo "----------------------------------------------------"

if [ "$MISSING" -ne 0 ]; then
    echo "One or more required commands are missing."
    echo "Install them via Synology Package Centre or entware before running Shredder."
    exit 1
fi

echo "All required dependencies satisfied."
exit 0
