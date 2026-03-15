#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# start-shredding.sh — root launcher
# Resolves its own directory so it works when invoked from any path
# (e.g. sudo /volume1/shredder/start-shredding.sh, or from cron).

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
exec sh "$SELF_DIR/bin/shredder.sh" "$@"
