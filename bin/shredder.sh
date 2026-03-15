#!/bin/sh
# Shredder — NAS external backup disk cleaner
# Copyright (C) 2025 James Wintermute
# Licensed under GNU GPLv3 (https://www.gnu.org/licenses/)
# This program comes with ABSOLUTELY NO WARRANTY.
#
# bin/shredder.sh — v1.7.0
# BusyBox / Synology compatible (no bash, no GNU date -d, no tail -r)

VERSION="1.7.0"
# Resolve BASE_DIR relative to this script's own location.
# bin/shredder.sh lives one level below the project root, so go up one.
# This means the project works correctly wherever it is installed or versioned.
BASE_DIR=$(cd "$(dirname "$0")/.." && pwd)
BIN_DIR="$BASE_DIR/bin"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/state"
PROGRESS_FILE="$STATE_DIR/progress.txt"

mkdir -p "$LOG_DIR" "$STATE_DIR"

HISTORY_FILE="$LOG_DIR/history.csv"
[ -f "$HISTORY_FILE" ] || \
    echo "timestamp,device,mode,passes,result,bytes,start_ts,end_ts,duration_s,logfile" \
    > "$HISTORY_FILE"

# ---------- terminal colours (only when stdout is a tty) ----------
if [ -t 1 ]; then
    RED='\033[31m'; GRN='\033[32m'; YLW='\033[33m'
    CYN='\033[36m'; BLD='\033[1m';  RST='\033[0m'
else
    RED=''; GRN=''; YLW=''; CYN=''; BLD=''; RST=''
fi

# ---------- utilities ----------

now_ts()  { date +%s; }
now_str() { date '+%Y-%m-%d %H:%M:%S'; }
pause()   { printf "Press Enter to continue...  "; read _r; }

hr() { printf '%s\n' "----------------------------------------------------"; }

list_usb_mounts() {
    mount | awk '/\/volumeUSB[0-9]+\/usbshare/ { print $1" "$3 }'
}

# Strip trailing partition digits: /dev/sdc1 -> /dev/sdc
device_from_partition() {
    echo "$1" | sed 's/[0-9]*$//'
}

# Refuse to operate on devices that look like system disks
safe_device() {
    case "$1" in
        /dev/sda*|/dev/sdb*|/dev/md*|/dev/vda*) return 1 ;;
    esac
    return 0
}

# Use kill -0 (POSIX) rather than ps | grep, which is fragile on BusyBox
current_running() {
    [ -f "$STATE_DIR/current.pid" ] || return 1
    pid=$(cat "$STATE_DIR/current.pid")
    kill -0 "$pid" 2>/dev/null
}

# Disk size in bytes — blockdev first, /sys fallback
get_size_bytes() {
    dev="$1"
    if command -v blockdev >/dev/null 2>&1; then
        sz=$(blockdev --getsize64 "$dev" 2>/dev/null)
        [ -n "$sz" ] && [ "$sz" -gt 0 ] 2>/dev/null && { echo "$sz"; return; }
    fi
    bname=$(basename "$dev")
    if [ -r "/sys/block/$bname/size" ]; then
        sectors=$(cat "/sys/block/$bname/size")
        echo $((sectors * 512))
        return
    fi
    echo 0
}

bytes_to_human() {
    b="$1"
    # One decimal place using integer arithmetic only (no bc/awk needed).
    # Multiply by 10 before dividing to get the tenths digit, then trim
    # trailing .0 so "4.0 TiB" displays as "4 TiB".
    _fmt() {
        whole=$(($1 / $2))
        tenths=$((($1 * 10 / $2) % 10))
        if [ "$tenths" -eq 0 ]; then
            printf '%d %s' "$whole" "$3"
        else
            printf '%d.%d %s' "$whole" "$tenths" "$3"
        fi
    }
    if   [ "$b" -ge 1099511627776 ]; then _fmt "$b" 1099511627776 TiB
    elif [ "$b" -ge 1073741824 ];    then _fmt "$b" 1073741824    GiB
    elif [ "$b" -ge 1048576 ];       then _fmt "$b" 1048576       MiB
    else printf '%d B' "$b"
    fi
}

disk_model() {
    blk="$1"
    ven=""; mod=""
    [ -r "/sys/block/$blk/device/vendor" ] && \
        ven=$(tr -d '[:space:]' < "/sys/block/$blk/device/vendor")
    [ -r "/sys/block/$blk/device/model"  ] && \
        mod=$(tr -d '[:space:]' < "/sys/block/$blk/device/model")
    out=$(printf '%s %s' "$ven" "$mod" | sed 's/^ *//;s/ *$//')
    [ -n "$out" ] && echo "$out" || echo "unknown"
}

# Format seconds as  Xh Ym Zs
elapsed_str() {
    s="$1"
    h=$((s / 3600)); m=$(( (s % 3600) / 60 )); ss=$((s % 60))
    printf '%dh %02dm %02ds' "$h" "$m" "$ss"
}

# ASCII progress bar:  [########............]  40%
make_bar() {
    pct="$1"
    filled=$((pct / 5)); i=0; bar=""
    while [ "$i" -lt "$filled" ]; do bar="${bar}#"; i=$((i+1)); done
    while [ "$i" -lt 20 ];        do bar="${bar}."; i=$((i+1)); done
    printf '[%s] %3d%%' "$bar" "$pct"
}

# ---------- background progress file monitor ----------
#
# Runs as a detached background job for the lifetime of each shred operation.
# Writes a human-readable progress.txt every 5 seconds.
# Terminates when done.txt appears (clean finish) or the pid file disappears
# (unexpected exit / SIGKILL).
#
# Usage: write_progress_loop <op_label> <whole_dev> <size_bytes> \
#                             <started_str> <start_ts> <log>
write_progress_loop() {
    op_label="$1"; whole_dev="$2"; size_bytes="$3"
    started_str="$4"; start_ts="$5"; log="$6"

    blk=$(basename "$whole_dev")
    model=$(disk_model "$blk")
    size_human=$(bytes_to_human "$size_bytes")

    while true; do
        ts_now=$(now_ts)
        elapsed=$(( ts_now - start_ts ))
        el_str=$(elapsed_str "$elapsed")

        # ---- clean completion ----
        if [ -f "$STATE_DIR/done.txt" ]; then
            result=$(cat "$STATE_DIR/done.txt")
            {
                hr
                printf '  SHREDDER — Operation Complete\n'
                hr
                echo ""
                printf '  Operation  : %s\n' "$op_label"
                printf '  Device     : %s   %s   %s\n' "$whole_dev" "$model" "$size_human"
                printf '  Started    : %s\n' "$started_str"
                printf '  Finished   : %s\n' "$(now_str)"
                printf '  Duration   : %s\n' "$el_str"
                printf '  Result     : %s\n' "$result"
                echo ""
                printf '  Log        : %s\n' "$log"
                hr
            } > "$PROGRESS_FILE"
            return
        fi

        # ---- unexpected exit (SIGKILL, crash, etc.) ----
        if ! current_running; then
            {
                hr
                printf '  SHREDDER — Operation Interrupted\n'
                hr
                echo ""
                printf '  Operation  : %s\n' "$op_label"
                printf '  Device     : %s   %s   %s\n' "$whole_dev" "$model" "$size_human"
                printf '  Started    : %s\n' "$started_str"
                printf '  Detected   : %s\n' "$(now_str)"
                printf '  Status     : INTERRUPTED (process not found)\n'
                echo ""
                printf '  Log        : %s\n' "$log"
                hr
            } > "$PROGRESS_FILE"
            return
        fi

        # ---- gather progress indicators ----

        # Current phase (written by the worker via phase.txt)
        phase=$(cat "$STATE_DIR/phase.txt" 2>/dev/null || echo "initialising")

        # Try to extract a percentage from the shred log.
        # GNU shred -v emits lines like:  /dev/sdc: pass 1/2 (random)...1.4GiB/2.0TiB 70%
        pct=$(grep -o '[0-9][0-9]*%' "$log" 2>/dev/null | tail -1 | tr -d '%')

        # For filesystem wipe: track the fill file size as a progress proxy
        fill_path=$(cat "$STATE_DIR/fill.path" 2>/dev/null)
        fill_bytes=0
        if [ -n "$fill_path" ] && [ -f "$fill_path" ]; then
            # ls -la field 5 is byte-size on BusyBox; avoids needing stat
            fill_bytes=$(ls -la "$fill_path" 2>/dev/null | awk '{print $5+0}')
        fi

        # ---- build progress display lines ----
        if [ -n "$pct" ] && [ "$pct" -gt 0 ] 2>/dev/null && [ "$pct" -le 100 ] 2>/dev/null; then
            # Full-device shred: percentage comes directly from shred -v output
            bar_str=$(make_bar "$pct")
            written_bytes=$((size_bytes * pct / 100))
            written_human=$(bytes_to_human "$written_bytes")
            eta_total=$((elapsed * 100 / pct))
            eta_rem=$((eta_total - elapsed))
            rate_mb=$(( elapsed > 0 ? written_bytes / elapsed / 1048576 : 0 ))
            pline="  Progress   : $bar_str"
            wline="  Written    : $written_human of $size_human"
            rline="  Rate       : ${rate_mb} MB/s"
            eline="  ETA        : approx $(elapsed_str "$eta_rem") remaining"

        elif [ "$fill_bytes" -gt 0 ] 2>/dev/null && [ "$size_bytes" -gt 0 ]; then
            # Filesystem wipe: derive everything from write rate so early-stage
            # progress is meaningful even when fill_bytes << 1% of disk size.

            written_human=$(bytes_to_human "$fill_bytes")

            # Integer percentage — may be 0 on a large disk early on
            pct=$((fill_bytes * 100 / size_bytes))
            [ "$pct" -gt 99 ] && pct=99

            # Bar label: show "<1%" rather than "0%" when we have data but
            # the percentage hasn't cleared the integer floor yet
            if [ "$pct" -eq 0 ]; then
                bar_str="[....................] <1%"
            else
                bar_str=$(make_bar "$pct")
            fi

            # Write rate in bytes/s — valid from the first non-zero elapsed second
            if [ "$elapsed" -gt 0 ]; then
                rate_bytes_s=$((fill_bytes / elapsed))
                rate_mb=$((rate_bytes_s / 1048576))
                rline="  Rate       : ${rate_mb} MB/s"

                # ETA from rate: how long to fill the remainder at current speed
                remaining_bytes=$((size_bytes - fill_bytes))
                if [ "$rate_bytes_s" -gt 0 ]; then
                    eta_rem=$((remaining_bytes / rate_bytes_s))
                    eline="  ETA        : approx $(elapsed_str "$eta_rem") remaining"
                else
                    eline="  ETA        : calculating..."
                fi
            else
                rline=""
                eline="  ETA        : calculating..."
            fi

            pline="  Progress   : $bar_str  (by fill-file size)"
            wline="  Written    : $written_human of ~$size_human"

        else
            pline="  Progress   : working..."
            wline=""
            rline=""
            eline="  ETA        : calculating..."
        fi

        # ---- write the progress file ----
        {
            hr
            printf '  SHREDDER — Progress Report\n'
            printf '  Updated    : %s  (refreshes every 5s)\n' "$(now_str)"
            hr
            echo ""
            printf '  Operation  : %s\n' "$op_label"
            printf '  Device     : %s   %s   %s\n' "$whole_dev" "$model" "$size_human"
            printf '  Started    : %s\n' "$started_str"
            printf '  Status     : RUNNING\n'
            echo ""
            printf '  Phase      : %s\n' "$phase"
            echo "$pline"
            [ -n "$wline" ] && echo "$wline"
            [ -n "$rline" ] && echo "$rline"
            echo "$eline"
            printf '  Elapsed    : %s\n' "$el_str"
            echo ""
            printf '  Log        : %s\n' "$log"
            hr
        } > "$PROGRESS_FILE"

        sleep 5
    done
}

# ---------- shred workers ----------

run_full_device_shred() {
    whole_dev="$1"; log="$2"; passes="$3"; size_bytes="$4"; start_ts="$5"

    printf '[%s] FULL DEVICE SHRED started: %s  passes=%s\n' \
        "$(now_str)" "$whole_dev" "$passes" >> "$log"
    echo "Pass 1 of $passes (random overwrite)" > "$STATE_DIR/phase.txt"

    # shred -v writes per-pass progress to stderr; redirect both to log
    shred -v -n "$passes" -z "$whole_dev" >> "$log" 2>&1
    rc=$?

    [ "$rc" -eq 0 ] && result="SUCCESS" || result="ERROR (exit $rc)"
    printf '[%s] finished  rc=%s\n' "$(now_str)" "$rc" >> "$log"

    end_ts=$(now_ts)
    duration=$((end_ts - start_ts))
    printf '%s,%s,full-device,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(now_str)" "$whole_dev" "$passes" "$result" \
        "$size_bytes" "$start_ts" "$end_ts" "$duration" "$log" \
        >> "$HISTORY_FILE"

    echo "$result" > "$STATE_DIR/done.txt"
    rm -f "$STATE_DIR/phase.txt"
}

run_fs_wipe() {
    mnt="$1"; log="$2"; size_bytes="$3"; start_ts="$4"; secure="$5"
    # secure=1 adds a urandom pass before the zero fill (slow on NAS CPUs)
    # secure=0 (default) does zero fill only — full disk speed, suitable for
    # backup rotation where the goal is cleaning data, not forensic denial

    if [ "$secure" = "1" ]; then
        total_phases=3
    else
        total_phases=2
    fi

    printf '[%s] FILESYSTEM WIPE started: %s  secure=%s\n' \
        "$(now_str)" "$mnt" "$secure" >> "$log"

    # --- Phase 1: clear existing files ---
    echo "Phase 1 of ${total_phases}: clearing existing files" > "$STATE_DIR/phase.txt"
    printf '[%s] clearing files\n' "$(now_str)" >> "$log"
    ( cd "$mnt" && rm -rf ./* ./.??* 2>/dev/null ) || \
        printf '[%s] warn: could not fully clear %s\n' "$(now_str)" "$mnt" >> "$log"
    sync

    # --- Phase 2 (secure only): urandom fill ---
    # /dev/urandom is CPU-bound on NAS hardware with no entropy acceleration.
    # On a 4 TiB disk this takes 1000+ hours. Only used when explicitly requested.
    if [ "$secure" = "1" ]; then
        FILL_RAND="$mnt/.shredder-fill-rand"
        echo "Phase 2 of 3: random overwrite fill (slow — CPU-bound)" > "$STATE_DIR/phase.txt"
        echo "$FILL_RAND" > "$STATE_DIR/fill.path"
        printf '[%s] starting random fill\n' "$(now_str)" >> "$log"
        dd if=/dev/urandom of="$FILL_RAND" bs=1M 2>>"$log" || true
        sync
        rm -f "$FILL_RAND"
        rm -f "$STATE_DIR/fill.path"
        zero_phase=3
    else
        zero_phase=2
    fi

    # --- Final phase: zero fill (runs at full disk speed) ---
    FILL_ZERO="$mnt/.shredder-fill-zero"
    echo "Phase ${zero_phase} of ${total_phases}: zero fill" > "$STATE_DIR/phase.txt"
    echo "$FILL_ZERO" > "$STATE_DIR/fill.path"
    printf '[%s] starting zero fill\n' "$(now_str)" >> "$log"
    dd if=/dev/zero of="$FILL_ZERO" bs=1M 2>>"$log" || true
    sync
    rm -f "$FILL_ZERO"
    rm -f "$STATE_DIR/fill.path"

    end_ts=$(now_ts)
    duration=$((end_ts - start_ts))
    mode_csv=$([ "$secure" = "1" ] && echo "fs-wipe-secure" || echo "fs-wipe-quick")
    printf '[%s] filesystem wipe complete\n' "$(now_str)" >> "$log"
    printf '%s,%s,%s,0,SUCCESS,%s,%s,%s,%s,%s\n' \
        "$(now_str)" "$mnt" "$mode_csv" \
        "$size_bytes" "$start_ts" "$end_ts" "$duration" "$log" \
        >> "$HISTORY_FILE"

    echo "SUCCESS" > "$STATE_DIR/done.txt"
    rm -f "$STATE_DIR/phase.txt"
}

# ---------- menu actions ----------

action_list_disks() {
    printf "${BLD}Detected USB mounts:${RST}\n"
    hr
    list_usb_mounts | while read -r part mnt; do
        whole=$(device_from_partition "$part")
        blk=$(basename "$whole")
        size=$(bytes_to_human "$(get_size_bytes "$whole")")
        model=$(disk_model "$blk")
        printf "  %s  ->  %s\n" "$part" "$mnt"
        printf "    ${BLD}Disk:${RST}  %-8s  %s\n" "$size" "$model"
        hr
    done
    [ "$(list_usb_mounts | wc -l)" -eq 0 ] && \
        printf "${YLW}  No USB mounts detected.${RST}\n"
}

action_start_shred() {
    if current_running; then
        printf "${YLW}A shred is already running (PID %s).${RST}\n" \
            "$(cat "$STATE_DIR/current.pid")"
        echo "Check progress with option 3."
        return
    fi

    mounts=$(list_usb_mounts)
    if [ -z "$mounts" ]; then
        printf "${RED}No USB disks mounted — plug one in first.${RST}\n"
        return
    fi

    printf "${BLD}Select a USB mount to shred:${RST}\n"
    hr
    i=1
    echo "$mounts" | while read -r part mnt; do
        whole=$(device_from_partition "$part")
        blk=$(basename "$whole")
        size=$(bytes_to_human "$(get_size_bytes "$whole")")
        model=$(disk_model "$blk")
        printf "  %d)  %s -> %s   [%s  %s]\n" "$i" "$part" "$mnt" "$size" "$model"
        i=$((i+1))
    done
    hr
    printf "Choose number: "
    read choice

    sel=$(echo "$mounts" | awk "NR==$choice")
    part=$(echo "$sel" | awk '{print $1}')
    mnt=$(echo "$sel"  | awk '{print $2}')
    [ -z "$part" ] && { printf "${RED}Invalid choice.${RST}\n"; return; }

    whole_dev=$(device_from_partition "$part")
    blk=$(basename "$whole_dev")
    size_bytes=$(get_size_bytes "$whole_dev")
    size_human=$(bytes_to_human "$size_bytes")
    model=$(disk_model "$blk")

    echo
    printf "${BLD}Wipe mode:${RST}\n"
    echo "  1)  Quick wipe     — delete files + zero fill  [default, full disk speed]"
    echo "  2)  Secure wipe    — delete files + random fill + zero fill  [very slow on NAS]"
    echo "  3)  Full device shred  — forensic, entire device, partition table included"
    printf "Mode [1]: "
    read mode
    [ -z "$mode" ] && mode=1

    case "$mode" in
        1) mode_label="Quick Filesystem Wipe"; secure_flag=0 ;;
        2) mode_label="Secure Filesystem Wipe"; secure_flag=1 ;;
        3) mode_label="Full Device Shred"; secure_flag=0 ;;
        *) printf "${RED}Invalid mode.${RST}\n"; return ;;
    esac

    # Warn user if they chose secure wipe
    if [ "$mode" -eq 2 ]; then
        echo
        printf "${YLW}${BLD}  NOTE: Secure wipe uses /dev/urandom which is CPU-bound on Synology NAS.${RST}\n"
        printf "${YLW}  On a 4 TiB disk this random fill phase may take 1000+ hours.${RST}\n"
        printf "${YLW}  Quick wipe (mode 1) is sufficient for backup rotation.${RST}\n"
        echo
        printf "  Are you sure you want secure wipe? Type YES to continue, or press Enter to go back: "
        read sec_confirm
        [ "$sec_confirm" != "YES" ] && { printf "${YLW}Returning to menu.${RST}\n"; return; }
    fi

    echo
    hr
    printf "${RED}${BLD}  WARNING — THIS OPERATION IS DESTRUCTIVE AND IRREVERSIBLE${RST}\n"
    hr
    printf "  Mode    : %s\n" "$mode_label"
    printf "  Device  : %s   (%s  %s)\n" "$whole_dev" "$size_human" "$model"
    printf "  Mount   : %s\n" "$mnt"
    hr

    pc=""
    if [ "$mode" -eq 3 ]; then
        if ! safe_device "$whole_dev"; then
            printf "${RED}Refusing — %s looks like a system disk.${RST}\n" "$whole_dev"
            return
        fi
        printf "Pass count [default 2]: "
        read pc
        [ -z "$pc" ] && pc=2
        mode_label="Full Device Shred (${pc}-pass + zero)"
        printf "  Passes  : %s random + final zero\n" "$pc"
        hr
    fi

    printf "Type YES to proceed: "
    read confirm
    [ "$confirm" != "YES" ] && { printf "${YLW}Aborted.${RST}\n"; return; }

    ts=$(date +%Y%m%d-%H%M%S)
    started_str=$(now_str)
    start_ts=$(now_ts)

    # Clear all previous state
    rm -f "$STATE_DIR/done.txt"  "$STATE_DIR/phase.txt" \
          "$STATE_DIR/fill.path" "$STATE_DIR/current.pid" \
          "$STATE_DIR/current.dev" "$STATE_DIR/current.log"

    echo
    if [ "$mode" -eq 3 ]; then
        log="$LOG_DIR/shred-${ts}-${blk}.log"
        echo "$whole_dev" > "$STATE_DIR/current.dev"
        echo "$log"       > "$STATE_DIR/current.log"

        printf "Unmounting %s ...\n" "$mnt"
        umount "$mnt" 2>/dev/null || \
            printf "${YLW}  warn: could not unmount — proceeding anyway${RST}\n"

        (
            run_full_device_shred "$whole_dev" "$log" "$pc" "$size_bytes" "$start_ts"
            sleep 8    # brief pause so the monitor can write its final "Complete" state
            rm -f "$STATE_DIR/current.pid" "$STATE_DIR/current.dev" \
                  "$STATE_DIR/current.log" "$STATE_DIR/done.txt"
        ) &
        pid=$!
        echo "$pid" > "$STATE_DIR/current.pid"

        # Start progress monitor as a separate background job
        write_progress_loop "$mode_label" "$whole_dev" \
            "$size_bytes" "$started_str" "$start_ts" "$log" &

        printf "${GRN}Full-device shred started in background (PID %s)${RST}\n" "$pid"
    else
        log="$LOG_DIR/fswipe-${ts}-$(basename "$part").log"
        echo "$part" > "$STATE_DIR/current.dev"
        echo "$log"  > "$STATE_DIR/current.log"

        (
            run_fs_wipe "$mnt" "$log" "$size_bytes" "$start_ts" "$secure_flag"
            sleep 8
            rm -f "$STATE_DIR/current.pid" "$STATE_DIR/current.dev" \
                  "$STATE_DIR/current.log" "$STATE_DIR/done.txt"
        ) &
        pid=$!
        echo "$pid" > "$STATE_DIR/current.pid"

        write_progress_loop "$mode_label" "$whole_dev" \
            "$size_bytes" "$started_str" "$start_ts" "$log" &

        printf "${GRN}Filesystem wipe started in background (PID %s)${RST}\n" "$pid"
    fi

    printf "Progress file : %s\n" "$PROGRESS_FILE"
    printf "Log           : %s\n" "$log"
    echo
    echo "To monitor: watch -n5 cat \"$PROGRESS_FILE\""
    echo "  (or choose option 3 from this menu)"
}

action_progress() {
    # If nothing is running and no progress file exists, quick status and return.
    if ! current_running && [ ! -f "$PROGRESS_FILE" ]; then
        printf "${YLW}No active operation and no progress file found.${RST}\n"
        return
    fi

    # Live refresh loop.
    # Ctrl+C is trapped to break cleanly back to the menu rather than
    # killing the whole script.
    trap 'break' INT
    while true; do
        clear 2>/dev/null

        if [ -f "$PROGRESS_FILE" ]; then
            cat "$PROGRESS_FILE"
        else
            printf "${YLW}Waiting for progress file...${RST}\n"
            log=$(cat "$STATE_DIR/current.log" 2>/dev/null)
            if [ -n "$log" ] && [ -f "$log" ]; then
                echo ""; printf "Log tail:\n"; hr
                tail -10 "$log"
            fi
        fi

        echo ""
        printf "  ${YLW}Auto-refreshing every 5s — press Ctrl+C to return to menu${RST}\n"

        # Stop looping once the worker has written done.txt and exited.
        if [ -f "$STATE_DIR/done.txt" ] && ! current_running; then
            echo ""
            printf "  Operation complete. Press Enter to return to menu...\n"
            read _r
            break
        fi

        sleep 5
    done
    trap - INT
}

action_history() {
    count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$count" -le 1 ]; then
        echo "No history yet."
        return
    fi
    printf "${BLD}Shred history (last 10 entries):${RST}\n"
    hr
    printf "  %-20s  %-18s  %-16s  %-7s  %-9s  %s\n" \
        "Timestamp" "Device" "Mode" "Passes" "Result" "Duration"
    hr
    # Skip header row, take last 10, format with awk
    # CSV fields: timestamp(1) device(2) mode(3) passes(4) result(5)
    #             bytes(6) start_ts(7) end_ts(8) duration_s(9) logfile(10)
    tail -n 10 "$HISTORY_FILE" | grep -v '^timestamp' | awk -F, '{
        dur = $9 + 0
        h   = int(dur / 3600)
        m   = int((dur % 3600) / 60)
        printf "  %-20s  %-18s  %-16s  %-7s  %-9s  %dh %02dm\n",
            $1, $2, $3, $4, $5, h, m
    }'
    hr
}

action_cancel() {
    if ! current_running; then
        printf "${YLW}No active operation to cancel.${RST}\n"
        return
    fi

    pid=$(cat "$STATE_DIR/current.pid" 2>/dev/null)
    dev=$(cat "$STATE_DIR/current.dev" 2>/dev/null)
    log=$(cat "$STATE_DIR/current.log" 2>/dev/null)
    phase=$(cat "$STATE_DIR/phase.txt" 2>/dev/null || echo "unknown")
    # BusyBox stat may not support -c; fall back to current time if unavailable
    start_ts=$(stat -c %Y "$STATE_DIR/current.pid" 2>/dev/null || now_ts)

    echo
    hr
    printf "${RED}${BLD}  WARNING — This will stop the active shred operation immediately.${RST}\n"
    hr
    printf "  PID     : %s\n" "$pid"
    printf "  Device  : %s\n" "$dev"
    printf "  Phase   : %s\n" "$phase"
    [ -n "$log" ] && printf "  Log     : %s\n" "$log"
    hr
    printf "${YLW}  The disk will be in a PARTIALLY WIPED state and should not be\n"
    printf "  used for backups until a full wipe has been completed.${RST}\n"
    hr
    echo
    printf "Type YES to cancel the operation, or press Enter to leave it running: "
    read confirm
    [ "$confirm" != "YES" ] && { printf "${GRN}Operation left running.${RST}\n"; return; }

    # Kill the entire process group to catch any dd/shred child processes.
    # SIGTERM first to allow tidy exit, then SIGKILL if still alive after 3s.
    kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 3 ]; do
        sleep 1; i=$((i+1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
    fi

    # Clean up any fill files left behind on the mount
    fill_path=$(cat "$STATE_DIR/fill.path" 2>/dev/null)
    if [ -n "$fill_path" ] && [ -f "$fill_path" ]; then
        printf "Removing partial fill file %s ...\n" "$fill_path"
        rm -f "$fill_path"
    fi

    # Record cancellation in history
    end_ts=$(now_ts)
    duration=$((end_ts - start_ts))
    if [ -n "$log" ]; then
        printf '[%s] CANCELLED by user (PID %s killed)\n' "$(now_str)" "$pid" >> "$log"
    fi
    printf '%s,%s,CANCELLED,0,CANCELLED,0,%s,%s,%s,%s\n' \
        "$(now_str)" "$dev" \
        "$start_ts" "$end_ts" "$duration" "${log:-none}" \
        >> "$HISTORY_FILE"

    # Write a final progress file so option 3 shows the cancelled state
    {
        hr
        printf '  SHREDDER — Operation Cancelled\n'
        hr
        echo ""
        printf '  Device     : %s\n' "$dev"
        printf '  Cancelled  : %s\n' "$(now_str)"
        printf '  Phase      : %s (at time of cancel)\n' "$phase"
        printf '  Status     : CANCELLED — disk is partially wiped\n'
        echo ""
        printf '  The disk should not be used until a full wipe has been completed.\n'
        echo ""
        [ -n "$log" ] && printf '  Log        : %s\n' "$log"
        hr
    } > "$PROGRESS_FILE"

    # Clear all state files
    rm -f "$STATE_DIR/current.pid" "$STATE_DIR/current.dev" \
          "$STATE_DIR/current.log" "$STATE_DIR/phase.txt" \
          "$STATE_DIR/fill.path"   "$STATE_DIR/done.txt"

    echo
    printf "${YLW}Operation cancelled. Check option 3 for final status.${RST}\n"
}

action_check_deps() {
    if [ -x "$BIN_DIR/check-deps.sh" ]; then
        sh "$BIN_DIR/check-deps.sh"
    else
        # Inline fallback if check-deps.sh is missing
        printf "${BLD}Dependency check (inline):${RST}\n"
        hr
        for cmd in shred dd mount umount awk sed date ps kill sync df; do
            if command -v "$cmd" >/dev/null 2>&1; then
                printf "  ${GRN}[OK]${RST}    %s\n" "$cmd"
            else
                printf "  ${RED}[MISS]${RST}  %s\n" "$cmd"
            fi
        done
        hr
    fi
}

action_estimate() {
    mounts=$(list_usb_mounts)
    if [ -z "$mounts" ]; then
        printf "${RED}No USB disks mounted.${RST}\n"
        return
    fi

    printf "${BLD}Select a mount to benchmark:${RST}\n"
    hr
    i=1
    echo "$mounts" | while read -r part mnt; do
        printf "  %d)  %s -> %s\n" "$i" "$part" "$mnt"
        i=$((i+1))
    done
    printf "Choose number: "
    read choice

    sel=$(echo "$mounts" | awk "NR==$choice")
    part=$(echo "$sel" | awk '{print $1}')
    mnt=$(echo "$sel"  | awk '{print $2}')
    [ -z "$part" ] && { printf "${RED}Invalid choice.${RST}\n"; return; }

    whole_dev=$(device_from_partition "$part")
    size_bytes=$(get_size_bytes "$whole_dev")
    size_human=$(bytes_to_human "$size_bytes")
    model=$(disk_model "$(basename "$whole_dev")")

    echo
    printf "  Disk : %s   %s   %s\n" "$whole_dev" "$size_human" "$model"
    echo
    echo "  Running 60s write benchmark on $mnt ..."
    echo "  (progress is printed every 10s to this terminal)"
    hr

    if [ -x "$BIN_DIR/estimate.sh" ]; then
        rate_mb=$(sh "$BIN_DIR/estimate.sh" "$mnt")
    else
        echo "  estimate.sh not found — assuming 120 MB/s"
        rate_mb=120
    fi
    [ -z "$rate_mb" ] || ! [ "$rate_mb" -gt 0 ] 2>/dev/null && rate_mb=120

    hr
    printf "  Measured write rate : ${BLD}%s MB/s${RST}\n" "$rate_mb"
    hr

    rate_bytes=$((rate_mb * 1024 * 1024))
    printf "  %-38s  %s\n" "Mode" "Estimated time"
    hr
    for passes in 1 2 3; do
        # passes × random + 1 × zero = passes+1 total full-disk writes
        total_bytes=$((size_bytes * (passes + 1)))
        secs=$((total_bytes / rate_bytes))
        h=$((secs / 3600)); m=$(( (secs % 3600) / 60 ))
        printf "  %-38s  %dh %02dm\n" \
            "Full device shred — ${passes}-pass + zero" "$h" "$m"
    done
    # Filesystem wipe: random fill + zero fill ≈ 2 × disk size
    fs_secs=$((size_bytes * 2 / rate_bytes))
    h=$((fs_secs / 3600)); m=$(( (fs_secs % 3600) / 60 ))
    printf "  %-38s  %dh %02dm\n" "Filesystem wipe (non-destructive)" "$h" "$m"
    hr
}

show_header() {
    clear 2>/dev/null
    printf "${CYN}${BLD}=== SHREDDER v%s  —  %s ===${RST}\n\n" \
        "$VERSION" "$(date '+%Y-%m-%d')"
}

# ---------- main loop ----------
while :; do
    show_header
    echo "  1)  List USB disks"
    echo "  2)  Start wipe / shred"
    echo "  3)  Check progress"
    echo "  4)  Show history"
    echo "  5)  Check dependencies"
    echo "  6)  Estimate shred time"
    if current_running; then
        printf "  ${RED}7)  Cancel active operation${RST}\n"
    fi
    echo "  0)  Exit"
    echo
    printf "Choose: "
    read opt
    echo
    case "$opt" in
        1) action_list_disks;  pause ;;
        2) action_start_shred; pause ;;
        3) action_progress ;;
        4) action_history;     pause ;;
        5) action_check_deps;  pause ;;
        6) action_estimate;    pause ;;
        7) action_cancel;      pause ;;
        0) exit 0 ;;
        *) printf "${RED}Unknown option.${RST}\n"; sleep 1 ;;
    esac
done
