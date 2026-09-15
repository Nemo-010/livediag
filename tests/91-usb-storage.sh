#!/bin/sh
# livediag: USB mass storage detection and a safe read-only mount.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "usb-storage" "USB storage" "Peripherals"

usb_disks() {
    for d in /sys/block/sd*; do
        [ -e "$d/device" ] || continue
        real=$(readlink -f "$d/device" 2>/dev/null)
        case "$real" in
        *"/usb"*) printf '%s\n' "${d##*/}" ;;
        esac
    done
}

before=$(usb_disks)
info="USB storage now: ${before:-none}"

if [ -z "$before" ]; then
    if ! lg_ui_available; then
        lg_skip "no USB storage attached"
    fi
    if ! lg_ui_yesno "$info

Insert a USB stick or an external drive, then press OK.  We will wait up to 60 seconds for it to appear."; then
        lg_skip "USB storage test cancelled"
    fi
fi

disk=""
i=0
while [ "$i" -lt 30 ]; do
    for d in $(usb_disks); do
        case " $before " in
        *" $d "*) ;;
        *) disk=$d ;;
        esac
    done
    [ -z "$before" ] && disk=$(usb_disks | head -n1)
    [ -n "$disk" ] && break
    sleep 2
    i=$((i + 1))
done
[ -z "$disk" ] && disk=$(printf '%s\n' $before | head -n1)

if [ -z "$disk" ]; then
    lg_ui_warn "$info

No USB storage device appeared.  Try another port and check dmesg for 'sd ... Attached SCSI removable disk'."
    lg_fail "no USB storage device detected"
fi

size=$(awk '{ printf "%.1f", $1 * 512 / 1000000000 }' "/sys/block/$disk/size" 2>/dev/null)
model=$(cat "/sys/block/$disk/device/model" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')
part=""
for p in /sys/block/"$disk"/"$disk"*; do
    [ -d "$p" ] || continue
    case "${p##*/}" in
    "$disk") ;;
    *) part=${p##*/} ;;
    esac
done

label=""
fstype=""
if lg_have blkid && [ -n "${part:-}" ]; then
    label=$(blkid "/dev/$part" 2>/dev/null | sed 's/.*LABEL="\([^"]*\)".*/\1/')
    fstype=$(blkid "/dev/$part" 2>/dev/null | sed 's/.*TYPE="\([^"]*\)".*/\1/')
fi

info="Device: /dev/$disk
Model: ${model:-unknown}
Size: ${size:-?} GB
Partition: ${part:-none}
Filesystem: ${fstype:-unknown}${label:+ label=$label}"

LG_CLEANUP_FN="lg_usb_cleanup"
lg_usb_cleanup() { umount "$LG_SESSION/mnt-usb" 2>/dev/null; }

# Safe read-only mount, never a write.
read_test="not attempted"
if [ -n "$part" ] && [ "$(id -u)" = "0" ]; then
    if lg_ui_yesno "$info

Mount the partition read-only and list its top level?  Nothing will be written."; then
        mp="$LG_SESSION/mnt-usb"
        mkdir -p "$mp" 2>/dev/null
        if lg_try 15 mount -o ro,nosuid,nodev "/dev/$part" "$mp" 2>"$LG_SESSION/usb-mount.log"; then
            files=$(ls -A "$mp" 2>/dev/null | head -n 12 | tr '\n' ' ')
            read_test="read ok: ${files:-empty volume}"
            umount "$mp" 2>/dev/null
        else
            read_test="mount failed: $(tail -n1 "$LG_SESSION/usb-mount.log" 2>/dev/null)"
        fi
    fi
fi

info="$info
Read test: $read_test"

lg_ui_info "$info"
lg_pass "/dev/$disk ${size:-?} GB ${fstype:-?}; $read_test"
