#!/bin/sh
# livediag: enumerate block devices, describe media and read SMART health.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "storage-disk" "Disks" "Storage"

[ -d /sys/block ] || lg_skip "no /sys/block"

devices=""
for d in /sys/block/*; do
    [ -e "$d" ] || continue
    n=${d##*/}
    case "$n" in
    loop* | ram* | zram* | dm-* | md* | sr*) continue ;;
    esac
    devices="$devices $n"
done

[ -n "$devices" ] || lg_skip "no block devices found"

info=""
bad=""
for n in $devices; do
    d="/sys/block/$n"
    sectors=$(cat "$d/size" 2>/dev/null)
    [ -n "$sectors" ] || sectors=0
    gb=$(awk -v s="$sectors" 'BEGIN { printf "%.1f", s * 512 / 1000000000 }')
    model=$(cat "$d/device/model" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')
    [ -n "$model" ] || model=$(cat "$d/device/name" 2>/dev/null)
    [ -n "$model" ] || model="generic"
    rota=$(cat "$d/queue/rotational" 2>/dev/null)
    case "$rota" in
    1) media="HDD" ;;
    0) media="SSD" ;;
    *) media="?" ;;
    esac
    if [ -r "$d/device/type" ] && [ "$(cat "$d/device/type" 2>/dev/null)" = "0" ]; then
        media="disk"
    fi
    info="$info
/dev/$n  ${gb} GB  $media  $model"
done

smarted=0
smart_bad=0
if lg_have smartctl; then
    scan=$(lg_try 15 smartctl --scan 2>/dev/null | awk '{print $1}' | head -n 12)
    [ -n "$scan" ] || scan=$(for n in $devices; do [ -b "/dev/$n" ] && echo "/dev/$n"; done)
    for dev in $scan; do
        [ -b "$dev" ] || continue
        smarted=$((smarted + 1))
        out=$(lg_try 20 smartctl -H "$dev" 2>/dev/null)
        if printf '%s\n' "$out" | grep -q 'FAILED!'; then
            smart_bad=$((smart_bad + 1))
            info="$info
SMART $dev: FAILED"
        elif printf '%s\n' "$out" | grep -q 'PASSED'; then
            info="$info
SMART $dev: passed"
        else
            info="$info
SMART $dev: unavailable"
        fi
    done
else
    info="$info

SMART: smartctl not installed"
fi

# eMMC / UFS wear counters, useful on phones and cheap laptops.
for n in $devices; do
    lt="/sys/block/$n/device/life_time"
    [ -r "$lt" ] || continue
    info="$info
eMMC $n wear (SLC/MLC): $(cat "$lt" 2>/dev/null)"
done

info="Block devices:$info"

if [ "$smart_bad" -gt 0 ]; then
    lg_ui_error "$info

At least one disk reported failing SMART health."
    lg_fail "$smart_bad of $smarted disks failed SMART"
fi

lg_ui_info "$info"
if [ "$smarted" -gt 0 ]; then
    lg_pass "$smarted disk(s) checked; SMART clean"
else
    lg_pass "block devices enumerated; SMART tool unavailable"
fi
