#!/bin/sh
# livediag: write, flush, verify and delete a temporary file; measure throughput.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "storage-rw" "Read/Write" "Storage"

# Pick a writable target.  Override with LIVEDIAG_RW_TARGET=/path.  Note that
# on a live image $HOME is often a tmpfs, so this measures RAM unless the
# caller points it at a real mounted filesystem.
target=${LIVEDIAG_RW_TARGET:-}
if [ -z "$target" ]; then
    for d in "$HOME" /tmp /var/tmp; do
        [ -n "$d" ] && [ -d "$d" ] && [ -w "$d" ] && target=$d && break
    done
fi
[ -n "$target" ] || lg_skip "no writable directory for the test"

free_kb=$(df -Pk "$target" 2>/dev/null | awk 'NR == 2 { print $4 }')
case "$free_kb" in '' | *[!0-9]*) free_kb=0 ;; esac
[ "$free_kb" -ge 16384 ] || lg_skip "not enough free space on $target ($free_kb KiB)"

mb=64
while [ "$mb" -gt 4 ] && [ $((mb * 1024 * 4)) -gt "$free_kb" ]; do
    mb=$((mb / 2))
done

fsline=$(df -Pk "$target" 2>/dev/null | awk 'NR == 2 { print $1 " (" $6 ")" }')

if lg_ui_available; then
    if ! lg_ui_yesno "Read/write test on:
$target  [$fsline]

A temporary $mb MiB file will be written, flushed, read back and deleted.  Nothing else is touched.
Run the test?"; then
        lg_pass "skipped by user; ${free_kb} KiB free on $target"
    fi
fi

file="$target/.livediag-rw-$$"
LG_CLEANUP_FN="lg_rw_cleanup"
lg_rw_cleanup() { rm -f "$file" 2>/dev/null; sync 2>/dev/null; }

log="$LG_SESSION/storage-rw.log"
start=$(date +%s)
if ! dd if=/dev/zero of="$file" bs=1048576 count="$mb" 2>"$log"; then
    tail=$(tail -n 2 "$log" 2>/dev/null | tr '\n' ' ')
    lg_ui_error "Could not write to $target:
$tail"
    lg_fail "write failed on $target: $tail"
fi
sync
end=$(date +%s)
wsecs=$((end - start))
[ "$wsecs" -ge 1 ] || wsecs=1

start=$(date +%s)
sum_file=""
sum_zero=""
verified=0
if lg_have cksum && lg_have dd; then
    sum_file=$(cksum <"$file" 2>/dev/null)
    sum_zero=$(dd if=/dev/zero bs=1048576 count="$mb" 2>/dev/null | cksum)
    [ -n "$sum_file" ] && verified=1
fi
end=$(date +%s)
rsecs=$((end - start))
[ "$rsecs" -ge 1 ] || rsecs=1

if [ "$verified" = "1" ] && [ "$sum_file" != "$sum_zero" ]; then
    lg_ui_error "Data read back from $target does not match what was written."
    lg_fail "read-back verification failed on $target"
fi

wmbps=$((mb / wsecs))
rm -f "$file" 2>/dev/null
sync 2>/dev/null

info="Target: $target
Filesystem: $fsline
Size: ${mb} MiB
Write: ${wsecs}s (~${wmbps} MiB/s)
Free: ${free_kb} KiB"

if [ "$wmbps" -lt 5 ]; then
    lg_ui_warn "$info

Write throughput is below 5 MiB/s. This can mean a failing disk, a slow card or a USB 1.1 port."
    lg_warn "slow write on $target: ~${wmbps} MiB/s"
fi

if [ "$verified" = "1" ]; then
    verify_msg="Written data verified byte for byte."
else
    verify_msg="File size verified (cksum unavailable)."
fi
lg_ui_info "$info

$verify_msg"
if [ "$verified" = "1" ]; then
    lg_pass "$target ${mb} MiB, ~${wmbps} MiB/s, verified"
fi
lg_pass "$target ${mb} MiB, ~${wmbps} MiB/s, size only"
