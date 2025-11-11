#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# start-shredding.sh — Shredder v1.0.4 (clean header, colours, disk info)
# BusyBox/Synology friendly
#

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
    echo "${CYN}${BLD}== SHREDDER v1.0.4 — $(date +%Y-%m-%d) ==${RST}"
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
    mount | awk '/\/volumeUSB[0-9]+\/usbshare/ {
        dev=$1; mnt=$3;
        printf "%s %s\n", dev, mnt
    }'
}

dev_to_block() {
    devpath="$1"
    base=$(basename "$devpath")
    echo "$base" | sed 's/[0-9]*$//'
}

block_human_size() {
    blk="$1"
    szfile="/sys/block/$blk/size"
    if [ -r "$szfile" ]; then
        sectors=$(cat "$szfile")
        bytes=$((sectors * 512))
        if [ "$bytes" -ge 1099511627776 ]; then
            tb=$((bytes / 1099511627776))
            echo "${tb}TB"
        elif [ "$bytes" -ge 1073741824 ]; then
            gb=$((bytes / 1073741824))
            echo "${gb}GB"
        else
            mb=$((bytes / 1048576))
            echo "${mb}MB"
        fi
    else
        echo "unknown"
    fi
}

block_model() {
    blk="$1"
    vfile="/sys/block/$blk/device/vendor"
    mfile="/sys/block/$blk/device/model"
    ven=""; mod=""
    [ -r "$vfile" ] && ven=$(tr -d '[:space:]' < "$vfile")
    [ -r "$mfile" ] && mod=$(tr -d '[:space:]' < "$mfile")
    if [ -n "$ven$mod" ]; then
        echo "$ven $mod" | sed 's/^ *//;s/ *$//'
    else
        echo ""
    fi
}

fs_info() {
    mnt="$1"
    if [ -n "$mnt" ]; then
        df -Th "$mnt" 2>/dev/null | tail -1 | awk '{printf "%s, %s used of %s", $2, $4, $3}'
    fi
}

describe_mount() {
    dev="$1"
    mnt="$2"
    blk=$(dev_to_block "$dev")
    size=$(block_human_size "$blk")
    model=$(block_model "$blk")
    fs=$(fs_info "$mnt")

    echo "$dev -> $mnt"
    printf "   ${BLD}Disk:${RST} %s %s\n" "$size" "$model"
    [ -n "$fs" ] && printf "   ${BLD}FS:${RST}   %s\n" "$fs"
}

check_disks() {
    show_header
    echo "${BLD}Detected USB mounts:${RST}"
    idx=1
    list_usb_mounts | while read -r dev mnt; do
        printf "  %d. " "$idx"
        describe_mount "$dev" "$mnt"
        idx=$((idx+1))
    done
    [ "$idx" -eq 1 ] && echo "${YLW}No USB mounts detected.${RST}"
    echo
    printf "Press Enter to continue..."
    read dummy
}

start_shred() {
    show_header
    usb_lines=$(list_usb_mounts)
    if [ -z "$usb_lines" ]; then
        echo "${RED}No USB mounts found. Plug in a disk and try again.${RST}"
        printf "Press Enter to continue..."
        read dummy
        return
    fi

    echo "${BLD}Select a USB mount to shred:${RST}"
    i=1
    echo "$usb_lines" | while read -r dev mnt; do
        printf " %d) %s -> %s\n" "$i" "$dev" "$mnt"
        i=$((i+1))
    done

    printf "Choose number: "
    read choice

    sel=$(echo "$usb_lines" | awk "NR==$choice {print}")
    if [ -z "$sel" ]; then
        echo "${RED}Invalid selection.${RST}"
        printf "Press Enter to continue..."
        read dummy
        return
    fi

    sel_dev=$(echo "$sel" | awk '{print $1}')
    sel_mnt=$(echo "$sel" | awk '{print $2}')

    show_header
    echo "${BLD}You selected:${RST}"
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
        *) echo "${RED}Invalid mode.${RST}"; printf "Press Enter to continue..."; read dummy; return;;
    esac

    echo
    echo "${RED}${BLD}About to perform ${mode_name}${RST}"
    echo "${RED}Target: $sel_dev mounted on $sel_mnt${RST}"
    echo
    printf "Type YES to continue: "
    read confirm
    if [ "$confirm" != "YES" ]; then
        echo "${YLW}Aborted by user.${RST}"
        printf "Press Enter to continue..."
        read dummy
        return
    fi

    echo
    echo "${GRN}Starting shred on $sel_dev ($sel_mnt) in mode $mode...${RST}"
    echo "${YLW}(this is where you call your real shredding backend script)${RST}"
    echo
    printf "Press Enter to continue..."
    read dummy
}

show_history() {
    show_header
    echo "${BLD}Shred history (placeholder)${RST}"
    printf "Press Enter to continue..."
    read dummy
}

check_deps() {
    show_header
    echo "${BLD}Checking dependencies...${RST}"
    missing=0
    for cmd in mount df awk sed; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo " - ${RED}$cmd missing${RST}"
            missing=1
        else
            echo " - ${GRN}$cmd OK${RST}"
        fi
    done
    echo
    if [ "$missing" -eq 0 ]; then
        echo "${GRN}All required commands present.${RST}"
    else
        echo "${RED}Some commands are missing. Please install/fix before shredding.${RST}"
    fi
    printf "Press Enter to continue..."
    read dummy
}

estimate_shred() {
    show_header
    echo "${BLD}Shred estimate — calculate approx. time${RST}"
    echo "(placeholder) — we can base this on disk size above"
    printf "Press Enter to continue..."
    read dummy
}

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
        3) show_header; echo "(progress placeholder)"; printf "Press Enter..."; read dummy ;;
        4) show_history ;;
        5) check_deps ;;
        6) estimate_shred ;;
        0) exit 0 ;;
        *) echo "${RED}Invalid choice${RST}"; sleep 1 ;;
    esac
done
