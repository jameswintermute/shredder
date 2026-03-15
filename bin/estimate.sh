#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# bin/estimate.sh — live 60s write benchmark
# v1.7.0
#
# Usage  : sh estimate.sh <mountpoint>
# Stdout : measured MB/s (integer) — suitable for capture by caller
# Stderr : live progress updates for the terminal

MNT="$1"

[ -z "$MNT" ]    && { echo "Usage: $0 <mountpoint>" >&2; exit 1; }
[ ! -d "$MNT" ]  && { printf "Error: mountpoint not found: %s\n" "$MNT" >&2; exit 1; }

TESTFILE="$MNT/.shredder-speedtest.$$"
CHUNK_BYTES=$((100 * 1024 * 1024))   # 100 MiB per dd call
START=$(date +%s)
BYTES_WRITTEN=0
LAST_REPORT=-1
DURATION=60

printf "Benchmarking writes for %ds — progress every 10s ...\n" "$DURATION" >&2

while true; do
    dd if=/dev/zero of="$TESTFILE" bs=1M count=100 conv=fsync 2>/dev/null || break
    BYTES_WRITTEN=$((BYTES_WRITTEN + CHUNK_BYTES))

    NOW=$(date +%s)
    ELAPSED=$((NOW - START))

    # Print a live update to the terminal every 10s
    REPORT_SLOT=$((ELAPSED / 10))
    if [ "$REPORT_SLOT" -gt "$LAST_REPORT" ]; then
        MiB=$((BYTES_WRITTEN / 1024 / 1024))
        RATE=$(( ELAPSED > 0 ? BYTES_WRITTEN / ELAPSED / 1024 / 1024 : 0 ))
        printf "  %2ds : %4d MiB written  (~%d MB/s so far)\n" \
            "$ELAPSED" "$MiB" "$RATE" >&2
        LAST_REPORT=$REPORT_SLOT
    fi

    [ "$ELAPSED" -ge "$DURATION" ] && break
done

rm -f "$TESTFILE" 2>/dev/null

END=$(date +%s)
ELAPSED=$((END - START))
[ "$ELAPSED" -le 0 ] && { echo "0"; exit 0; }

RATE_BYTES=$((BYTES_WRITTEN / ELAPSED))
RATE_MB=$((RATE_BYTES / 1024 / 1024))

printf "  Done : sustained write rate = %d MB/s\n" "$RATE_MB" >&2

# Stdout result for capture by the caller
echo "$RATE_MB"
exit 0
