#!/bin/sh
# livediag: PCI and USB devices the kernel has no driver for.
#
# This is how the suite notices an unsupported laptop: the hardware is
# present, the kernel enumerated it, and nothing claims it.  That is a WARN,
# not a failure - it is the machine's nature, not a broken installation.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "hardware-unsupported" "Unsupported hardware" "Hardware"

pci=""
for d in /sys/bus/pci/devices/*; do
    [ -e "$d" ] || continue
    [ -e "$d/driver" ] && continue
    cls=$(cat "$d/class" 2>/dev/null)
    # Host/PCI/ISA bridges are always present and never drive a user device.
    case "$cls" in
    0x06*) continue ;;
    esac
    vid=$(cat "$d/vendor" 2>/dev/null)
    did=$(cat "$d/device" 2>/dev/null)
    [ -n "$vid" ] && [ -n "$did" ] && pci="$pci ${vid#0x}:${did#0x}"
done

usb=""
for d in /sys/bus/usb/devices/*-*; do
    [ -e "$d" ] || continue
    [ -e "$d/driver" ] && continue
    bound=0
    for i in "$d"/*/driver; do
        [ -e "$i" ] && bound=1
    done
    [ "$bound" = "1" ] && continue
    vid=$(cat "$d/idVendor" 2>/dev/null)
    pid=$(cat "$d/idProduct" 2>/dev/null)
    [ -n "$vid" ] && [ -n "$pid" ] && usb="$usb $vid:$pid"
done

pci=${pci# }
usb=${usb# }

total=$(printf '%s\n' $pci $usb | grep -c . 2>/dev/null)
case "$total" in '' | *[!0-9]*) total=0 ;; esac

info="PCI devices without a driver: ${pci:-none}
USB devices without a driver: ${usb:-none}"

if [ "$total" -gt 0 ]; then
    lg_ui_warn "$info

These devices will not work under Linux until a driver exists for them.  They are listed so the report is honest about what this machine cannot do."
    lg_warn "unbound PCI: ${pci:-none}; unbound USB: ${usb:-none}"
fi

lg_ui_info "$info"
lg_pass "all PCI and USB devices have a kernel driver"
