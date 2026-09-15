#!/bin/sh
# livediag: RAM and swap capacity, error counters and an optional memtester pass.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "core-mem" "Memory" "Core"

[ -r /proc/meminfo ] || lg_skip "no /proc/meminfo (not a Linux system?)"

meminfo_kb() {
    awk -v k="$1" '$1 == k ":" { print $2; exit }' /proc/meminfo
}

total_kb=$(meminfo_kb MemTotal)
free_kb=$(meminfo_kb MemAvailable)
[ -n "$free_kb" ] || free_kb=$(meminfo_kb MemFree)
swap_total_kb=$(meminfo_kb SwapTotal)
swap_free_kb=$(meminfo_kb SwapFree)

mib() { [ -n "$1" ] && echo $(( $1 / 1024 )); }

info="RAM total:     $(mib "$total_kb") MiB
RAM available: $(mib "$free_kb") MiB
Swap total:    $(mib "${swap_total_kb:-0}") MiB
Swap free:     $(mib "${swap_free_kb:-0}") MiB"

# EDAC corrected/uncorrected counters, when the platform exposes them.
edac_ce=0
edac_ue=0
for f in /sys/devices/system/edac/mc/mc*/ce_count; do
    [ -r "$f" ] || continue
    edac_ce=$((edac_ce + $(cat "$f" 2>/dev/null || echo 0)))
done
for f in /sys/devices/system/edac/mc/mc*/ue_count; do
    [ -r "$f" ] || continue
    edac_ue=$((edac_ue + $(cat "$f" 2>/dev/null || echo 0)))
done
[ "$edac_ce" -ge 0 ] 2>/dev/null || edac_ce=0
if [ "$edac_ce" -gt 0 ] || [ "$edac_ue" -gt 0 ]; then
    info="$info
EDAC errors:   corrected=$edac_ce uncorrected=$edac_ue"
fi

hard_fail=0
if lg_have dmesg; then
    if dmesg 2>/dev/null | grep -Eqi 'EDAC.*(UE|uncorrected)|Machine check.*(error|bank)' \
        && ! dmesg 2>/dev/null | grep -Eqi 'mce:.*(No|disabled)'; then
        hard_fail=1
    fi
fi

result="$(mib "$total_kb") MiB RAM, $(mib "${swap_total_kb:-0}") MiB swap"
note=""

# Optional deep test when memtester is available.
if lg_have memtester && [ -n "$free_kb" ] && [ "$free_kb" -gt 131072 ]; then
    default_mb=$((total_kb / 1024 / 8))
    [ "$default_mb" -gt 256 ] && default_mb=256
    [ "$default_mb" -lt 32 ] && default_mb=32
    if lg_ui_yesno "$info

Run a memory correctness pass with memtester?  This allocates up to ${default_mb} MiB and takes about 30 seconds.
Choose No to skip the slow part."; then
        mb=$(lg_ui_input "How many MiB should memtester test?" "$default_mb")
        case "$mb" in
        '' | *[!0-9]*) mb=$default_mb ;;
        esac
        out="$LG_SESSION/memtester.log"
        if lg_busy "Testing ${mb} MiB of RAM..." \
            "lg_try 60 memtester ${mb}M 1" "$out"; then
            note="; memtester ${mb} MiB ok"
        else
            tail=$(tail -n 3 "$out" 2>/dev/null | tr '\n' ' ')
            lg_ui_error "memtester reported a problem:
$tail"
            lg_fail "memory error during memtester ${mb} MiB: $tail"
        fi
    else
        note="; memtester skipped"
    fi
else
    note="; deep memory test unavailable (memtester not installed)"
fi

if [ "$hard_fail" = "1" ]; then
    lg_ui_warn "$info

The kernel log mentions machine-check or uncorrected EDAC errors. This can indicate failing RAM."
    lg_fail "$result; kernel logged machine-check/EDAC errors"
fi

lg_ui_info "$info"
lg_pass "$result$note"
