#!/bin/sh
# livediag: Bluetooth adapter power, discovery and optional pairing.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-bluetooth" "Bluetooth" "Network"

hci=""
for d in /sys/class/bluetooth/hci*; do
    [ -e "$d" ] || continue
    hci=${d##*/}
    break
done

if [ -z "$hci" ] && ! lg_have bluetoothctl; then
    lg_skip "no Bluetooth adapter detected"
fi

lg_have rfkill && rfkill unblock bluetooth >/dev/null 2>&1
if lg_have bluetoothctl; then
    lg_try 10 bluetoothctl power on >/dev/null 2>&1
fi

ctrl=""
if lg_have bluetoothctl; then
    ctrl=$(lg_try 10 bluetoothctl list 2>/dev/null | awk '{print $2; exit}')
fi

info="Adapter: ${hci:-none}${ctrl:+ ($ctrl)}"

if ! lg_have bluetoothctl; then
    lg_ui_warn "$info

The adapter exists but the bluetoothctl tool is missing, so it cannot be driven from here."
    lg_skip "$hci present; bluetoothctl unavailable"
fi

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

A 12 second scan will run.  Put your phone or headphones into pairing/discoverable mode now.
Start the scan?"; then
    lg_skip "Bluetooth scan cancelled"
fi

raw="$LG_SESSION/bt-scan.raw"
clean="$LG_SESSION/bt-scan.txt"
{
    printf 'power on\nagent on\ndefault-agent\nscan on\n'
    sleep 12
    printf 'devices\nscan off\nquit\n'
} | lg_try 45 bluetoothctl >"$raw" 2>&1

tr -d '\r\033' <"$raw" | sed 's/\[[0-9;]*m//g' >"$clean" 2>/dev/null

devices=$(grep '^Device ' "$clean" 2>/dev/null | sort -u)
count=$(printf '%s\n' "$devices" | grep -c '^Device ' 2>/dev/null)
case "$count" in '' | *[!0-9]*) count=0 ;; esac

list=""
if [ "$count" -gt 0 ]; then
    list=$(printf '%s\n' "$devices" | sed 's/^Device /  /' | head -n 12)
fi

if [ "$count" -eq 0 ]; then
    lg_ui_warn "$info

The scan finished but no devices were seen.  Bluetooth is powered, but the adapter or the antenna may not be working, or nothing was in reach."
    lg_warn "$hci scanned, 0 devices found"
fi

info="$info
Devices found: $count
$list"

if ! lg_ui_yesno "$info

Try pairing with one of them?  You will pick it from a list and confirm on both devices."; then
    lg_pass "$hci scan found $count device(s)"
fi

set --
while IFS= read -r line; do
    [ -n "$line" ] || continue
    mac=${line#Device }
    mac=${mac%% *}
    name=${line#Device "$mac" }
    [ "$name" = "$line" ] && name="unknown"
    set -- "$@" "$mac" "$name" "Bluetooth device"
done <<EOF
$(printf '%s\n' "$devices" | head -n 20)
EOF

[ "$#" -ge 3 ] || lg_pass "$hci scan found $count device(s); nothing selected"
target=$(lg_ui_menu "Pair Bluetooth" "Choose a device to pair with." "$@") || lg_pass "$hci scan found $count device(s)"

raw="$LG_SESSION/bt-pair.raw"
{
    printf 'power on\nagent on\ndefault-agent\npair %s\n' "$target"
    sleep 15
    printf 'trust %s\nconnect %s\ninfo %s\nquit\n' "$target" "$target" "$target"
} | lg_try 60 bluetoothctl >"$raw" 2>&1
tr -d '\r\033' <"$raw" | sed 's/\[[0-9;]*m//g' >"$clean" 2>/dev/null

if grep -qi 'Paired: yes' "$clean" 2>/dev/null; then
    lg_ui_info "Paired with $target."
    lg_pass "$hci paired with $target, scan found $count"
fi

lg_ui_warn "Pairing with $target did not complete.  This is often a confirmation timeout on the other device."
lg_warn "$hci could not pair with $target (scan found $count)"
