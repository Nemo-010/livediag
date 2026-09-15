#!/bin/sh
# livediag: CPU model, topology, clock and a short arithmetic stability check.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "core-cpu" "CPU" "Core"

[ -r /proc/cpuinfo ] || lg_skip "no /proc/cpuinfo (not a Linux system?)"

model=$(awk -F: '
    /^[[:space:]]*(model name|cpu model|Hardware|Processor|Model)/ {
        sub(/^[[:space:]]+/, "", $2); print $2; exit
    }' /proc/cpuinfo)
[ -n "$model" ] || model="unknown"

vendor=$(awk -F: '
    /^[[:space:]]*(vendor_id|CPU implementer)/ {
        sub(/^[[:space:]]+/, "", $2); print $2; exit
    }' /proc/cpuinfo)
[ -n "$vendor" ] || vendor=$(uname -m)

logical=$(lg_ncpu)
sockets=$(awk -F: '
    /^physical id/ { gsub(/[[:space:]]/, "", $2); if (!seen[$2]++) c++ }
    END { print (c + 0) }' /proc/cpuinfo)
[ "$sockets" -gt 0 ] 2>/dev/null || sockets=1
cores=$(awk -F: '/^core id/ { print $2 }' /proc/cpuinfo 2>/dev/null | sort -u | wc -l | tr -d ' ')
[ "$cores" -gt 0 ] 2>/dev/null || cores="$logical"

freq_khz=""
for f in /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq \
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq \
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; do
    if [ -r "$f" ]; then
        freq_khz=$(cat "$f" 2>/dev/null)
        [ -n "$freq_khz" ] && break
    fi
done

load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)

info="CPU:    $model
Vendor: $vendor
Arch:   $(uname -m)
Sockets/cores/threads: $sockets / $cores / $logical"
[ -n "$freq_khz" ] && info="$info
Max clock: $((freq_khz / 1000)) MHz"
[ -n "$load" ] && info="$info
Load now: $load"

# Arithmetic digest: exercises integer maths on every logical CPU.  Failure
# here means the CPU executed the loop incorrectly, which is a real fault.
expected=20000100000
worst=""
i=0
while [ "$i" -lt "$logical" ]; do
    val=$(awk 'BEGIN { s = 0; for (i = 1; i <= 200000; i++) s += i; printf "%.0f", s }' 2>/dev/null)
    [ "$val" = "$expected" ] || worst="$val"
    i=$((i + 1))
done

if [ -n "$worst" ]; then
    lg_ui_error "$info

Arithmetic check FAILED: expected $expected, got $worst."
    lg_fail "$model; $logical threads; arithmetic check returned $worst"
fi

lg_ui_info "$info

Arithmetic check passed on $logical threads."
lg_pass "$model; ${sockets}s/${cores}c/${logical}t; ${freq_khz:-?} kHz"
