#!/bin/sh
# livediag: USB controllers, devices and hotplug detection.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "usb-devices" "USB" "Peripherals"

usb_count() {
    n=0
    for d in /sys/bus/usb/devices/*-*; do
        [ -e "$d" ] && n=$((n + 1))
    done
    printf '%s' "$n"
}

controllers=""
if lg_have lspci; then
    controllers=$(lspci 2>/dev/null | grep -i 'USB controller' | sed 's/^[0-9a-f.:]* //')
fi

tree=""
if lg_have lsusb; then
    tree=$(lsusb 2>/dev/null | head -n 20)
fi

before=$(usb_count)
info="USB devices attached: $before
Controllers:
${controllers:-unknown}
Devices:
${tree:-lsusb unavailable}"

if ! lg_ui_available; then
    lg_pass "$before USB device(s)"
fi

if ! lg_ui_yesno "$info

Plug in a USB device now (a stick, mouse, phone, anything), then press OK.
We will check that the kernel notices it."; then
    lg_pass "$before USB device(s); hotplug test skipped"
fi

after=$before
i=0
while [ "$i" -lt 15 ]; do
    after=$(usb_count)
    [ "$after" -gt "$before" ] && break
    sleep 1
    i=$((i + 1))
done

if [ "$after" -gt "$before" ]; then
    lg_ui_info "USB enumeration works: $before -> $after devices."
    lg_pass "hotplug detected ($before -> $after)"
fi

lg_ui_warn "No new USB device appeared.  Try another port and cable; check dmesg for 'usb ... new device'."
lg_warn "USB hotplug not detected ($before -> $after)"
