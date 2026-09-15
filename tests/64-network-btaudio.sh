#!/bin/sh
# livediag: Bluetooth headset/speaker output.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-btaudio" "Bluetooth audio" "Network"

cards=""
[ -n "$(command -v pactl 2>/dev/null)" ] &&
    cards=$(pactl list cards short 2>/dev/null | awk '/bluez/{print $2}' | tr '\n' ' ')
sinks=""
[ -n "$(command -v pactl 2>/dev/null)" ] &&
    sinks=$(pactl list short sinks 2>/dev/null | awk '/bluez/{print $2}' | tr '\n' ' ')

connected=""
if lg_have bluetoothctl; then
    connected=$(lg_try 10 bluetoothctl devices Connected 2>/dev/null | sed 's/^Device //;s/ / - /' | head -n 5 | tr '\n' '; ')
fi

if [ -z "$cards" ] && [ -z "$sinks" ]; then
    lg_ui_info "No Bluetooth audio device is connected.

Pair a headset or speaker first (the Bluetooth test can help), then run this test again."
    lg_skip "no Bluetooth audio endpoint connected"
fi

info="Bluetooth audio card(s): ${cards:-none}
Sink(s): ${sinks:-none}
Connected: ${connected:-none}"

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

A short tone will play through the Bluetooth device.  Continue?"; then
    lg_skip "Bluetooth audio test cancelled"
fi

out="$LG_SESSION/btaudio.log"
if ! lg_busy "Playing tone over Bluetooth..." "lg_play_tone" "$out"; then
    tail=$(tail -n 2 "$out" 2>/dev/null | tr '\n' ' ')
    lg_ui_warn "Playback over Bluetooth failed:
$tail"
    lg_fail "Bluetooth playback failed: $tail"
fi

if lg_ui_yesno "Did you hear the tone through the Bluetooth device?"; then
    lg_pass "$cards $sinks; tone audible"
fi

lg_warn "$cards present but tone not heard"
