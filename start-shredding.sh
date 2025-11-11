#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# Launcher script for Shredder — runs dependency checks and menu safely

BASE_DIR="/volume1/shredder"
BIN_DIR="$BASE_DIR/bin"
LOG_DIR="$BASE_DIR/logs"

echo "======================================================"
echo "        ⚠️  SHREDDER — DATA DESTRUCTION TOOL ⚠️"
echo "======================================================"
echo
echo "This tool will permanently destroy all data on selected disks."
echo "Ensure you have complete backups before continuing."
echo
printf "Type YES to confirm you wish to continue: "
read confirm
[ "$confirm" != "YES" ] && { echo "Aborted."; exit 1; }

# Run dependency check
if [ -x "$BIN_DIR/check-deps.sh" ]; then
    echo
    echo "Running dependency check..."
    sh "$BIN_DIR/check-deps.sh"
    if [ $? -ne 0 ]; then
        echo "Dependency check failed. Resolve missing commands before proceeding."
        exit 1
    fi
else
    echo "Dependency checker not found at $BIN_DIR/check-deps.sh"
    echo "Proceeding without dependency verification..."
fi

# Ensure log dir exists
mkdir -p "$LOG_DIR"

echo
echo "Launching Shredder main menu..."
sleep 2

if [ -x "$BIN_DIR/shredder.sh" ]; then
    sh "$BIN_DIR/shredder.sh"
else
    echo "Error: shredder.sh not found or not executable at $BIN_DIR/shredder.sh"
    exit 1
fi
