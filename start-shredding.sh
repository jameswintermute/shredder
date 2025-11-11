#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# start-shredding.sh — safe launcher for Shredder
# v1.0.3 — 2025-11-11

# Resolve script directory (BusyBox-safe)
SCRIPT_PATH="$(readlink "$0" 2>/dev/null || echo "$0")"
BASE_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

BIN_DIR="$BASE_DIR/bin"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/state"

export BASE_DIR BIN_DIR LOG_DIR STATE_DIR

echo "=== Shredder v1.0.3 — NAS external backup disk cleaner ==="
echo "Root directory: $BASE_DIR"
echo

if [ ! -x "$BIN_DIR/shredder.sh" ]; then
    echo "Error: could not find executable $BIN_DIR/shredder.sh"
    exit 1
fi

# Dependency check first
if [ -x "$BIN_DIR/check-deps.sh" ]; then
    echo "Performing dependency check..."
    sh "$BIN_DIR/check-deps.sh" || true
    echo
fi

# Launch main program
exec sh "$BIN_DIR/shredder.sh"
