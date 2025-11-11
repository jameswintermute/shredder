#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# Dependency checker — modelled on hasher's style

echo "Shredder dependency check:"

MISSING=0

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        printf " [OK]   %s\n" "$1"
    else
        printf " [MISS] %s\n" "$1"
        MISSING=1
    fi
}

check_cmd shred
check_cmd mount
check_cmd umount
check_cmd awk
check_cmd sed
check_cmd date
check_cmd ps

# optional but useful
if command -v blockdev >/dev/null 2>&1; then
    echo " [OK]   blockdev (for exact disk size)"
else
    echo " [WARN] blockdev not found — size will be estimated"
fi

if [ $MISSING -ne 0 ]; then
    echo
    echo "One or more required commands are missing. Install/enable them on the NAS first."
    exit 1
fi

echo
echo "All required dependencies found."
exit 0
