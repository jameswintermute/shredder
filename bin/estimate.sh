#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# estimate.sh — live 60s write benchmark for a mounted USB volume
# v1.0.3 — 2025-11-11
#
# Usage: ./estimate.sh /volumeUSB1/usbshare
# Prints measured MB/s to stdout

MNT="$1"

if [ -z "$MNT" ]; then
    echo "Usage: $0 <mountpoint>" >&2
    exit 1
fi

if [ ! -d "$MNT" ]; then
    echo "Error: mountpoint $MNT not found" >&2
    exit 1
fi

TESTFILE="$MNT/.shredder-speedtest.$$"
START=$(date +%s)
BYTES_WRITTEN=0

echo "Running 60s write test on $MNT ..."
while :; do
    dd if=/dev/zero of="$TESTFILE" bs=1M count=100 conv=fsync 2>/dev/null || break
    BYTES_WRITTEN=$((BYTES_WRITTEN + 104857600))
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    [ "$ELAPSED" -ge 60 ] && break
done

rm -f "$TESTFILE" 2>/dev/null

END=$(date +%s)
ELAPSED=$((END - START))
if [ "$ELAPSED" -le 0 ]; then
    echo "0"
    exit 0
fi

RATE_BYTES=$((BYTES_WRITTEN / ELAPSED))
RATE_MB=$((RATE_BYTES / 1024 / 1024))

echo "$RATE_MB"
exit 0
