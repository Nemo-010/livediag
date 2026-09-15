#!/bin/sh
# livediag: SD card reader detection and identification.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "sdcard" "SD card" "Peripherals"

hosts=""
for h in /sys/class/mmc_host/*; do
    [ -e "$h" ] || continue
    hosts="$hosts ${h##*/}"
done
[ -n "$hosts" ] || lg_skip "no MMC/SD host controller detected"

sd_cards() {
    for d in /sys/block/mmcblk*; do
        [ -e "$d" ] || continue
        [ "$(cat "$d/removable" 2>/dev/null)" = "1" ] || continue
        printf '%s\n' "${d##*/}"
    done
}

before=$(sd_cards)
info="MMC host(s):$hosts
Removable cards now: ${before:-none}"

if [ -z "$before" ]; then
    if ! lg_ui_available; then
        lg_skip "SD host present but no removable card inserted"
    fi
    if ! lg_ui_yesno "$info

Insert an SD card, then press OK.  We will wait up to 60 seconds."; then
        lg_skip "SD card test cancelled"
    fi
fi

card=""
i=0
while [ "$i" -lt 30 ]; do
    card=$(sd_cards | head -n1)
    [ -n "$card" ] && break
    sleep 2
    i=$((i + 1))
done
[ -z "$card" ] && card=$(printf '%s\n' $before | head -n1)

if [ -z "$card" ]; then
    lg_ui_warn "$hosts

No removable card was detected.  Check the slot, the card's write-protect switch and dmesg for 'mmc0: new'."
    lg_fail "no SD card detected"
fi

d="/sys/block/$card"
size=$(awk '{ printf "%.1f", $1 * 512 / 1000000000 }' "$d/size" 2>/dev/null)
name=$(cat "$d/device/name" 2>/dev/null)
serial=$(cat "$d/device/serial" 2>/dev/null)
cid=$(cat "$d/device/cid" 2>/dev/null)
ro=$(cat "$d/ro" 2>/dev/null)

info="Card: /dev/$card
Size: ${size:-?} GB
Name: ${name:-unknown}
Serial: ${serial:-unknown}
CID: ${cid:-unavailable}
Write-protected: ${ro:-?}"

lg_ui_info "$info"
lg_pass "/dev/$card ${size:-?} GB ${name:-unknown}"
