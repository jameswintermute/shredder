#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# start-shredding.sh — Shredder v1.0.8 (stateful progress: elapsed + ETA)
# BusyBox/Synology friendly
#

STATE_FILE="/tmp/shredder.state"
WORKFILE_NAME=".shredder-fill-rand"

# ---------- colours ----------
if [ -t 1 ]; then
    RED='\033[31m'
    GRN='\033[32m'
    YLW='\033[33m'
    BLU='\033[34m'
    MAG='\033[35m'
    CYN='\033[36m'
    BLD='\033[1m'
    RST='\033[0m'
else
    RED=''; GRN=''; YLW=''; BLU=''; MAG=''; CYN=''; BLD=''; RST=''
fi

# ---------- header ----------
show_header() {
    clear 2>/dev/null
    printf '%b\n' "${CYN}${BLD}== SHREDDER v1.0.8 — $(date +%Y-%m-%d) ==${RST}"
    cat <<'EOF'
==================================================
=                                                =
=              S H R E D D E R                   =
=         External USB Wipe Tool                 =
=                                                =
==================================================
EOF
    echo
}

# ---------- detect USB mounts ----------
list_usb_mounts() {
    mount | awk '/\/volumeUSB[0-9]+\/usbshare/ {printf "%s %s\n", $1, $3}'
}

dev_to_block() {
    base=$(basename "$1")
    echo "$base" | sed 's/[0-9]*$//'
}

block_human_size() {
    blk="$1"
    f="/sys/block/$blk/size"
    if [ -r "$f" ]; then
        sectors=$(cat "$f")
        bytes=$((sectors * 512))
        if [ "$bytes" -ge 1099511627776 ]; then
            echo "$((bytes / 1099511627776))TB"
        elif [ "$bytes" -ge 1073741824 ]; then
            echo "$((bytes / 1073741824))GB"
        else
            echo "$((bytes / 1048576))MB"
        fi
    else
        echo "unknown"
    fi
}

block_model() {
    blk="$1"
    v="/sys/block/$blk/device/vendor"
    m="/sys/block/$blk/device/model"
    ven=""; mod=""
    [ -r "$v" ] && ven=$(tr -d '[:space:]' < "$v")
    [ -r "$m" ] && mod=$(tr -d '[:space:]' < "$m")
    echo "$ven $mod" | sed 's/^ *//;s/ *$//'
}

fs_info() {
    mnt="$1"
    df -Th "$mnt" 2>/dev/null | tail -1 | awk '{printf "%s, %s used of %s", $2, $4, $3}'
}

describe_mount() {
    dev="$1"; mnt="$2"
    blk=$(dev_to_block "$dev")
    size=$(block_human_size "$blk")
    model=$(block_model "$blk")
    fs=$(fs_info "$mnt")
    echo "$dev -> $mnt"
    printf "   %b\n" "${BLD}Disk:${RST} $size $model"
    [ -n "$fs" ] && printf "   %b\n" "${BLD}FS:${RST}   $fs"
}

# ---------- human readable bytes ----------
human_bytes() {
    b="$1"
    if command -v bc >/dev/null 2>&1; then
        if [ "$b" -ge 1099511627776 ] 2>/dev/null; then
            printf "%.2fTB" "$(echo "$b / 1099511627776" | bc -l)"
        elif [ "$b" -ge 1073741824 ] 2>/dev/null; then
            printf "%.2fGB" "$(echo "$b / 1073741824" | bc -l)"
        elif [ "$b" -ge 1048576 ] 2>/dev/null; then
            printf "%.2fMB" "$(echo "$b / 1048576" | bc -l)"
        elif [ "$b" -ge 1024 ] 2>/dev/null; then
            printf "%.2fKB" "$(echo "$b / 1024" | bc -l)"
        else
            printf "%dB" "$b"
        fi
    else
        if [ "$b" -ge 1099511627776 ] 2>/dev/null; then
            printf "%dTB" $((b / 1099511627776))
        elif [ "$b" -ge 1073741824 ] 2>/dev/null; then
            printf "%dGB" $((b / 1073741824))
        elif [ "$b" -ge 1048576 ] 2>/dev/null; then
            printf "%dMB" $((b / 1048576))
        elif [ "$b" -ge 1024 ] 2>/dev/null; then
            printf "%dKB" $((b / 1024))
        else
            printf "%dB" "$b"
        fi
    fi
}

# ---------- duration ----------
format_duration() {
    s="$1"
    d=$((s / 86400)); s=$((s % 86400))
    h=$((s / 3600));  s=$((s % 3600))
    m=$((s / 60));    s=$((s % 60))
    out=""
    [ "$d" -gt 0 ] && out="$out${d}d "
    [ "$h" -gt 0 ] && out="$out${h}h "
    [ "$m" -gt 0 ] && out="$out${m}m "
    out="$out${s}s"
    echo "$out"
}

# ---------- check disks ----------
check_disks() {
    show_header
    printf '%b\n' "${BLD}Detected USB mounts:${RST}"
    usb=$(list_usb_mounts)
    if [ -z "$usb" ]; then
        printf '%b\n' "${YLW}No USB mounts detected.${RST}"
    else
        i=1
        echo "$usb" | while read -r dev mnt; do
            printf "  %d. " "$i"
            describe_mount "$dev" "$mnt"
            i=$((i+1))
        done
    fi
    echo
    printf "Press Enter to continue..."
    read _dummy
}

# ---------- progress ----------
check_progress() {
    while true; do
        show_header

        if [ -r "$STATE_FILE" ]; then
            # shellcheck disable=SC1090
            . "$STATE_FILE"
        else
            STATE_MOUNT=""
            STATE_START=""
            STATE_TOTAL=""
            STATE_WORKFILE=""
        fi

        found=0

        # if we have a state file, prefer that
        if [ -n "$STATE_MOUNT" ] && [ -n "$STATE_WORKFILE" ] && [ -f "$STATE_WORKFILE" ]; then
            mnt="$STATE_MOUNT"
            workfile="$STATE_WORKFILE"
            bytes_written=$(wc -c < "$workfile" 2>/dev/null)
            [ -z "$bytes_written" ] && bytes_written=0
            total_bytes="$STATE_TOTAL"
            pct=0
            if [ -n "$total_bytes" ] && [ "$total_bytes" -gt 0 ] 2>/dev/null; then
                pct=$((bytes_written * 100 / total_bytes))
            fi
            written_hr=$(human_bytes "$bytes_written")
            total_hr=$(human_bytes "$total_bytes")

            # elapsed from stored start
            elapsed_str=""
            eta_str="calculating..."
            if [ -n "$STATE_START" ]; then
                now=$(date +%s)
                elapsed=$((now - STATE_START))
                [ "$elapsed" -lt 0 ] && elapsed=0
                elapsed_str=$(format_duration "$elapsed")

                # ETA only if >60s and we wrote some data
                if [ "$elapsed" -ge 60 ] && [ "$bytes_written" -gt 0 ]; then
                    bps=$((bytes_written / elapsed))
                    if [ "$bps" -gt 0 ]; then
                        remaining=$((total_bytes - bytes_written))
                        if [ "$remaining" -le 0 ]; then
                            eta_str="complete"
                        else
                            eta_secs=$((remaining / bps))
                            eta_str=$(format_duration "$eta_secs")
                        fi
                    fi
                fi
            fi

            dd_pid=$(ps | awk '/dd/ && /\.shredder-fill-rand/ {print $1; exit}')

            printf '%b\n' "${BLD}Current shred in progress:${RST}"
            [ -n "$dd_pid" ] && printf " PID: %s\n" "$dd_pid"
            printf " Mount: %s\n" "$mnt"
            printf " Work file: %s\n" "$workfile"
            printf " Written: %s of %s (%s%%)\n" "$written_hr" "$total_hr" "$pct"
            [ -n "$elapsed_str" ] && printf " Elapsed: %s\n" "$elapsed_str"
            printf " ETA: %s\n" "$eta_str"
            found=1
        else
            # fall back to scan
            usb=$(list_usb_mounts)
            echo "$usb" | while read -r dev mnt; do
                wf="$mnt/$WORKFILE_NAME"
                if [ -f "$wf" ]; then
                    bytes_written=$(wc -c < "$wf" 2>/dev/null)
                    set -- $(df -k "$mnt" 2>/dev/null | tail -1)
                    total_kb=$2
                    total_bytes=$((total_kb * 1024))
                    pct=$((bytes_written * 100 / total_bytes))
                    printf '%b\n' "${BLD}Current shred in progress (no state file):${RST}"
                    printf " Mount: %s\n" "$mnt"
                    printf " Work file: %s\n" "$wf"
                    printf " Written: %s of %s (%s%%)\n" "$(human_bytes "$bytes_written")" "$(human_bytes "$total_bytes")" "$pct"
                    found=1
                fi
            done
        fi

        if [ "$found" -eq 0 ]; then
            printf '%b\n' "${YLW}No active shred operation detected.${RST}"
            printf "Press Enter to continue..."
            read _d
            return
        fi

        echo
        printf "Updating in 30 seconds... (Ctrl+C to return to menu)\n"
        sleep 30
    done
}

start_shred() {
    show_header
    usb=$(list_usb_mounts)
    if [ -z "$usb" ]; then
        printf '%b\n' "${RED}No USB mounts found.${RST}"
        printf "Press Enter to continue..."
        read _d
        return
    fi

    printf '%b\n' "${BLD}Select a USB mount to shred:${RST}"
    i=1
    echo "$usb" | while read -r dev mnt; do
        printf " %d) %s -> %s\n" "$i" "$dev" "$mnt"
        i=$((i+1))
    done

    printf "Choose number: "
    read choice

    sel=$(echo "$usb" | awk "NR==$choice {print}")
    if [ -z "$sel" ]; then
        printf '%b\n' "${RED}Invalid selection.${RST}"
        printf "Press Enter to continue..."
        read _d
        return
    fi

    sel_dev=$(echo "$sel" | awk '{print $1}')
    sel_mnt=$(echo "$sel" | awk '{print $2}')

    show_header
    printf '%b\n' "${BLD}You selected:${RST}"
    describe_mount "$sel_dev" "$sel_mnt"
    echo
    echo "Choose shred mode:"
    echo "  1) Filesystem-preserving wipe (default)"
    echo "  2) FULL device shred (forensic)"
    printf "Mode [1]: "
    read mode
    [ -z "$mode" ] && mode=1

    case "$mode" in
        1) mode_name="FILESYSTEM WIPE (non-destructive to partition table)";;
        2) mode_name="FULL DEVICE SHRED (ALL DATA, partition table included)";;
        *) printf '%b\n' "${RED}Invalid mode.${RST}"; printf "Press Enter..."; read _d; return;;
    esac

    echo
    printf '%b\n' "${RED}${BLD}About to perform ${mode_name}${RST}"
    printf '%b\n' "${RED}Target: $sel_dev mounted on $sel_mnt${RST}"
    echo
    printf "Type YES to continue: "
    read confirm
    if [ "$confirm" != "YES" ]; then
        printf '%b\n' "${YLW}Aborted by user.${RST}"
        printf "Press Enter to continue..."
        read _d
        return
    fi

    # capture start state BEFORE running backend
    start_epoch=$(date +%s)
    # total from df
    set -- $(df -k "$sel_mnt" 2>/dev/null | tail -1)
    total_kb=$2
    total_bytes=$((total_kb * 1024))
    workfile="$sel_mnt/$WORKFILE_NAME"

    {
        echo "STATE_START=$start_epoch"
        echo "STATE_MOUNT=$sel_mnt"
        echo "STATE_TOTAL=$total_bytes"
        echo "STATE_WORKFILE=$workfile"
    } > "$STATE_FILE"

    echo
    printf '%b\n' "${GRN}Starting shred on $sel_dev ($sel_mnt) in mode $mode...${RST}"
    printf '%b\n' "${YLW}(call your real backend here to create $workfile and fill it)${RST}"
    # e.g.:
    # dd if=/dev/urandom of="$workfile" bs=1M
    echo
    printf "Press Enter to continue..."
    read _d
}

show_history() {
    show_header
    printf '%b\n' "${BLD}Shred history (placeholder)${RST}"
    printf "Press Enter to continue..."
    read _d
}

check_deps() {
    show_header
    printf '%b\n' "${BLD}Checking dependencies...${RST}"
    for cmd in mount df awk sed wc; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf " - %b\n" "${GRN}$cmd OK${RST}"
        else
            printf " - %b\n" "${RED}$cmd missing${RST}"
        fi
    done
    printf "Press Enter to continue..."
    read _d
}

estimate_shred() {
    show_header
    printf '%b\n' "${BLD}Shred estimate — calculate approx. time${RST}"
    echo "(placeholder)"
    printf "Press Enter to continue..."
    read _d
}

# ---------- main loop ----------
while true; do
    show_header
    echo "1) Check external USB disks"
    echo "2) Start a new wipe/shred"
    echo "3) Check current progress"
    echo "4) Show history"
    echo "5) Check dependencies"
    echo "6) Shred estimate — calculate approx. time"
    echo "0) Exit"
    printf "Choose: "
    read ans
    case "$ans" in
        1) check_disks ;;
        2) start_shred ;;
        3) check_progress ;;
        4) show_history ;;
        5) check_deps ;;
        6) estimate_shred ;;
        0) exit 0 ;;
        *) printf '%b\n' "${RED}Invalid choice${RST}"; sleep 1 ;;
    esac
done
