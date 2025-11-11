#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# Launcher script for Shredder — runs dependency checks and menu safely
# v1.0.1 — 2025-11-11

BASE_DIR="/volume1/shredder"
BIN_DIR="$BASE_DIR/bin"
LOG_DIR="$BASE_DIR/logs"

echo "======================================================"
echo "           ⚠️  SHREDDER v1.0.1 — DATA TOOL ⚠️"
echo "======================================================"
echo
echo "This will either:"
echo " - (default) wipe the filesystem and zero the free space"
echo " - OR perform a full forensic device shred"
echo
printf "Type YES to continue: "
read confirm
[ "$confirm" != "YES" ] && { echo "Aborted."; exit 1; }

if [ -x "$BIN_DIR/check-deps.sh" ]; then
    echo
    echo "Running dependency check..."
    sh "$BIN_DIR/check-deps.sh" || { echo "Dependency check failed."; exit 1; }
else
    echo "Dependency checker not found at $BIN_DIR/check-deps.sh — continuing..."
fi

mkdir -p "$LOG_DIR"

echo
echo "Launching Shredder main menu (v1.0.1)..."
sleep 1

if [ -x "$BIN_DIR/shredder.sh" ]; then
    sh "$BIN_DIR/shredder.sh"
else
    echo "Error: shredder.sh not found at $BIN_DIR/shredder.sh"
    exit 1
fi
