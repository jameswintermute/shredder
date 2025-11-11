#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# Main menu and orchestration

BASE_DIR="/volume1/shredder"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/state"
mkdir -p "$LOG_DIR" "$STATE_DIR"

HISTORY_FILE="$LOG_DIR/history.csv"
[ -f "$HISTORY_FILE" ] || echo "timestamp,device,passes,result,bytes,start_ts,end_ts,logfile" > "$HISTORY_FILE"

now_iso() {
    date -Iseconds
}

pause() {
    printf "Press Enter to continue... "
    read _x
}

list_usb_mounts() {
    mount | grep '/volumeUSB' | awk '{print $1" "$3}'
}

device_from_mount() {
    dev="$1"
    base="$(echo "$dev" | sed 's/[0-9]*$//')"
    echo "$base"
}

safe_device() {
    case "$1" in
        /dev/sda*|/dev/sdb*|/dev/md*|/dev/vda*)
            return 1
            ;;
    esac
    return 0
}

current_running() {
    [ -f "$STATE_DIR/current.pid" ] && ps | grep -q "$(cat "$STATE_DIR/current.pid")"
}

get_size_bytes() {
    dev="$1"
    if command -v blockdev >/dev/null 2>&1; then
        blockdev --getsize64 "$dev" 2>/dev/null && return
    fi
    bname="$(basename "$dev")"
    if [ -r "/sys/block/$bname/size" ]; then
        sz="$(cat /sys/block/$bname/size)"
        echo $((sz * 512))
        return
    fi
    echo 0
}

action_list_disks() {
    echo "Detected USB mounts:"
    list_usb_mounts | nl -w2 -s'. '
    [ "$(list_usb_mounts | wc -l)" -eq 0 ] && echo "No USB disks mounted."
}

action_start_shred() {
    if current_running; then
        echo "A shred is already running (PID $(cat "$STATE_DIR/current.pid"))."
        echo "Check progress from menu option 3."
        return
    fi

    echo "Select a USB mount to shred:"
    mounts="$(list_usb_mounts)"
    if [ -z "$mounts" ]; then
        echo "No USB disks mounted under /volumeUSB — plug one in first."
        return
    fi

    i=1
    echo "$mounts" | while read dev mnt; do
        echo "$i) $dev -> $mnt"
        i=$((i+1))
    done

    printf "Choose number: "
    read choice

    sel="$(echo "$mounts" | sed -n "${choice}p")"
    dev="$(echo "$sel" | awk '{print $1}')"
    mnt="$(echo "$sel" | awk '{print $2}')"

    if [ -z "$dev" ]; then
        echo "Invalid choice."
        return
    fi

    whole_dev="$(device_from_mount "$dev")"

    if ! safe_device "$whole_dev"; then
        echo "Refusing to shred $whole_dev — looks like a system disk."
        return
    fi

    printf "Pass count [default 2]: "
    read pc
    [ -z "$pc" ] && pc=2

    echo "About to shred $whole_dev (mounted at $mnt) with $pc pass(es) + final zero."
    echo "This will destroy ALL data and partition info on that disk."
    printf "Type YES to continue: "
    read conf
    [ "$conf" != "YES" ] && { echo "Aborted."; return; }

    echo "Unmounting $mnt ..."
    umount "$mnt" 2>/dev/null || echo "warn: could not unmount $mnt — shred may fail if mounted."

    ts=$(date +%Y%m%d-%H%M%S)
    log="$LOG_DIR/shred-${ts}-$(basename "$whole_dev").log"

    echo "$whole_dev" > "$STATE_DIR/current.dev"
    echo "$log" > "$STATE_DIR/current.log"

    size_bytes=$(get_size_bytes "$whole_dev")

    (
        start_ts=$(date +%s)
        echo "[$(now_iso)] starting shred on $whole_dev passes=$pc" >>"$log"
        shred -v -n "$pc" -z "$whole_dev" >>"$log" 2>&1
        rc=$?
        end_ts=$(date +%s)
        result="success"
        [ $rc -ne 0 ] && result="error-$rc"
        echo "[$(now_iso)] finished shred rc=$rc" >>"$log"
        echo "$(now_iso),$whole_dev,$pc,$result,$size_bytes,$start_ts,$end_ts,$log" >>"$HISTORY_FILE"
        rm -f "$STATE_DIR/current.pid" "$STATE_DIR/current.dev" "$STATE_DIR/current.log"
    ) &

    pid=$!
    echo $pid > "$STATE_DIR/current.pid"
    echo "Shred started in background, PID $pid"
    echo "Log: $log"
}

action_progress() {
    if ! current_running; then
        echo "No shred currently running."
        lastlog="$(ls -1t "$LOG_DIR"/shred-*.log 2>/dev/null | head -n1)"
        [ -n "$lastlog" ] && { echo "Last log:"; tail -n 20 "$lastlog"; }
        return
    fi

    log="$(cat "$STATE_DIR/current.log" 2>/dev/null)"
    dev="$(cat "$STATE_DIR/current.dev" 2>/dev/null)"
    echo "Current shred on $dev"
    echo "Log: $log"

    if [ -f "$log" ]; then
        pct="$(grep -o '[0-9][0-9]*%$' "$log" | tail -n1)"
        echo "Progress: ${pct:-unknown}"
        echo "Last 20 lines:"
        tail -n 20 "$log"
    else
        echo "Log not found."
    fi
}

action_history() {
    if [ ! -f "$HISTORY_FILE" ]; then
        echo "No history yet."
        return
    fi
    echo "Shred history (last 20):"
    tail -n 20 "$HISTORY_FILE"
}

action_check_deps() {
    if [ -x "$BASE_DIR/check-deps.sh" ]; then
        sh "$BASE_DIR/check-deps.sh"
    else
        echo "Dependency checker not found at $BASE_DIR/check-deps.sh"
    fi
}

while :; do
    echo
    echo "=== Shredder ==="
    echo "1) Check external USB disks"
    echo "2) Start a new shred (default 2 passes)"
    echo "3) Check current shred progress"
    echo "4) Show shred history"
    echo "5) Check dependencies"
    echo "0) Exit"
    printf "Choose: "
    read opt
    case "$opt" in
        1) action_list_disks; pause ;;
        2) action_start_shred; pause ;;
        3) action_progress; pause ;;
        4) action_history; pause ;;
        5) action_check_deps; pause ;;
        0) exit 0 ;;
        *) echo "Unknown option" ;;
    esac
done
