#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# Main menu and orchestration
# v1.0.3 — 2025-11-11

BASE_DIR="/volume1/shredder"
BIN_DIR="$BASE_DIR/bin"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/state"
mkdir -p "$LOG_DIR" "$STATE_DIR"

HISTORY_FILE="$LOG_DIR/history.csv"
[ -f "$HISTORY_FILE" ] || echo "timestamp,device,mode,passes,result,bytes,start_ts,end_ts,logfile" > "$HISTORY_FILE"

now_iso() { date -Iseconds; }

pause() { printf "Press Enter to continue... "; read _x; }

list_usb_mounts() { mount | grep '/volumeUSB' | awk '{print $1" "$3}'; }

device_from_mount() { dev="$1"; base="$(echo "$dev" | sed 's/[0-9]*$//')"; echo "$base"; }

safe_device() {
    case "$1" in
        /dev/sda*|/dev/sdb*|/dev/md*|/dev/vda*) return 1 ;;
    esac
    return 0
}

current_running() { [ -f "$STATE_DIR/current.pid" ] && ps | grep -q "$(cat "$STATE_DIR/current.pid")"; }

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

bytes_to_human() {
    b="$1"
    if [ "$b" -ge 1099511627776 ]; then
        echo "$((b / 1099511627776)) TiB"
    elif [ "$b" -ge 1073741824 ]; then
        echo "$((b / 1073741824)) GiB"
    elif [ "$b" -ge 1048576 ]; then
        echo "$((b / 1048576)) MiB"
    else
        echo "$b bytes"
    fi
}

action_list_disks() {
    echo "Detected USB mounts:"
    list_usb_mounts | nl -w2 -s'. '
    [ "$(list_usb_mounts | wc -l)" -eq 0 ] && echo "No USB disks mounted."
}

run_full_device_shred() {
    whole_dev="$1"
    log="$2"
    passes="$3"
    size_bytes="$4"
    start_ts=$(date +%s)
    echo "[$(now_iso)] starting FULL DEVICE shred on $whole_dev passes=$passes" >>"$log"
    shred -v -n "$passes" -z "$whole_dev" >>"$log" 2>&1
    rc=$?
    end_ts=$(date +%s)
    result="success"
    [ $rc -ne 0 ] && result="error-$rc"
    echo "[$(now_iso)] finished full device shred rc=$rc" >>"$log"
    echo "$(now_iso),$whole_dev,full-device,$passes,$result,$size_bytes,$start_ts,$end_ts,$log" >>"$HISTORY_FILE"
}

run_fs_wipe() {
    mnt="$1"
    log="$2"
    start_ts=$(date +%s)
    echo "[$(now_iso)] starting FILESYSTEM WIPE on $mnt (preserve partition)" >>"$log"
    ( cd "$mnt" 2>/dev/null && rm -rf ./* ./.??* 2>/dev/null ) || echo "[$(now_iso)] warn: could not fully clear $mnt" >>"$log"
    dd if=/dev/urandom of="$mnt/.shredder-fill-rand" bs=1M 2>>"$log" || true
    sync
    rm -f "$mnt/.shredder-fill-rand"
    dd if=/dev/zero of="$mnt/.shredder-fill-zero" bs=1M 2>>"$log" || true
    sync
    rm -f "$mnt/.shredder-fill-zero"
    rc=$?
    end_ts=$(date +%s)
    result="success"
    [ $rc -ne 0 ] && result="error-$rc"
    echo "[$(now_iso)] finished filesystem wipe rc=$rc" >>"$log"
    echo "$(now_iso),$mnt,fs-wipe,0,$result,0,$start_ts,$end_ts,$log" >>"$HISTORY_FILE"
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

    echo
    echo "Choose shred mode:"
    echo "1) Filesystem-preserving wipe (default)"
    echo "2) FULL device shred (forensic)"
    printf "Mode [1]: "
    read mode
    [ -z "$mode" ] && mode=1

    if [ "$mode" -eq 2 ] 2>/dev/null; then
        if ! safe_device "$whole_dev"; then
            echo "Refusing to shred $whole_dev — looks like a system disk."
            return
        fi
        printf "Pass count [default 2]: "
        read pc
        [ -z "$pc" ] && pc=2
        echo "About to shred WHOLE DEVICE $whole_dev with $pc pass(es) + final zero."
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
            run_full_device_shred "$whole_dev" "$log" "$pc" "$size_bytes"
            rm -f "$STATE_DIR/current.pid" "$STATE_DIR/current.dev" "$STATE_DIR/current.log"
        ) &
        pid=$!
        echo $pid > "$STATE_DIR/current.pid"
        echo "Full-device shred started in background, PID $pid"
        echo "Log: $log"
    else
        echo "About to perform FILESYSTEM WIPE on $mnt (non-destructive to partition table)."
        printf "Type YES to continue: "
        read conf2
        [ "$conf2" != "YES" ] && { echo "Aborted."; return; }
        ts=$(date +%Y%m%d-%H%M%S)
        log="$LOG_DIR/fswipe-${ts}-$(basename "$dev").log"
        echo "$dev" > "$STATE_DIR/current.dev"
        echo "$log" > "$STATE_DIR/current.log"
        (
            run_fs_wipe "$mnt" "$log"
            rm -f "$STATE_DIR/current.pid" "$STATE_DIR/current.dev" "$STATE_DIR/current.log"
        ) &
        pid=$!
        echo $pid > "$STATE_DIR/current.pid"
        echo "Filesystem wipe started in background, PID $pid"
        echo "Log: $log"
    fi
}

action_progress() {
    if ! current_running; then
        echo "No shred currently running."
        lastlog="$(ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -n1)"
        [ -n "$lastlog" ] && { echo "Last log:"; tail -n 20 "$lastlog"; }
        return
    fi
    log="$(cat "$STATE_DIR/current.log" 2>/dev/null)"
    dev="$(cat "$STATE_DIR/current.dev" 2>/dev/null)"
    echo "Current operation on $dev"
    echo "Log: $log"
    if [ -f "$log" ]; then
        pct="$(grep -o '[0-9][0-9]*%$' "$log" | tail -n1)"
        [ -n "$pct" ] && echo "Progress: $pct"
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

action_estimate() {
    echo "Select a USB mount to estimate:"
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
    size_bytes=$(get_size_bytes "$whole_dev")
    size_human=$(bytes_to_human "$size_bytes")

    echo
    echo "Disk: $whole_dev (approx $size_human)"
    echo "Running live 60s speed test on: $mnt"
    if [ -x "$BIN_DIR/estimate.sh" ]; then
        rate_mb=$(sh "$BIN_DIR/estimate.sh" "$mnt")
    else
        echo "estimate.sh not found — falling back to 120MB/s"
        rate_mb=120
    fi

    [ -z "$rate_mb" ] && rate_mb=120
    if [ "$rate_mb" -le 0 ] 2>/dev/null; then
        rate_mb=120
    fi

    echo "Measured/assumed rate: ${rate_mb} MB/s"

    total_bytes=$((size_bytes * 3))
    rate_bytes=$((rate_mb * 1024 * 1024))
    if [ "$rate_bytes" -le 0 ]; then
        echo "Cannot calculate estimate (rate 0)."
        return
    fi
    seconds=$((total_bytes / rate_bytes))
    hours=$((seconds / 3600))
    rem=$((seconds % 3600))
    mins=$((rem / 60))

    echo "Estimated shred time (2-pass + zero): ~ ${hours}h ${mins}m"

    low=$((hours - 2))
    high=$((hours + 2))
    if [ $low -lt 1 ]; then low=1; fi
    echo "Planning window: between ${low}h and ${high}h"
}

while :; do
    echo
    echo "=== Shredder v1.0.3 — 2025-11-11 ==="
    echo "1) Check external USB disks"
    echo "2) Start a new wipe/shred"
    echo "3) Check current progress"
    echo "4) Show history"
    echo "5) Check dependencies"
    echo "6) Shred estimate — calculate approx. time"
    echo "0) Exit"
    printf "Choose: "
    read opt
    case "$opt" in
        1) action_list_disks; pause ;;
        2) action_start_shred; pause ;;
        3) action_progress; pause ;;
        4) action_history; pause ;;
        5) action_check_deps; pause ;;
        6) action_estimate; pause ;;
        0) exit 0 ;;
        *) echo "Unknown option" ;;
    esac
done
