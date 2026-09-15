#!/bin/sh
# livediag: game controller buttons and axes.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "gamepad" "Gamepad" "Peripherals"

js=""
for d in /dev/input/js*; do
    [ -c "$d" ] || continue
    js="$js $d"
done
js=${js# }

named=""
if [ -r /proc/bus/input/devices ]; then
    named=$(awk '/^N: Name=/ && tolower($0) ~ /(gamepad|game pad|joystick|controller)/ { sub(/^N: Name=/,""); print }' \
        /proc/bus/input/devices | head -n 3 | tr '\n' '; ')
fi

if [ -z "$js" ]; then
    if [ -n "$named" ]; then
        lg_ui_warn "A controller is known to the kernel ($named) but no /dev/input/js* node exists.  The joydev module is probably not loaded."
        lg_warn "controller present without js node"
    fi
    lg_skip "no game controller detected"
fi

first=$(printf '%s\n' $js | head -n1)
info="Joystick nodes:$js
Known name(s): ${named:-unknown}"

if ! lg_have jstest; then
    if lg_ui_available && lg_ui_yesno "$info

The jstest tool is not installed, so only a manual check is possible.
Press buttons on the controller and confirm below."; then
        if lg_ui_yesno "Did the controller respond in your desktop or game?"; then
            lg_pass "$first responds"
        fi
    fi
    lg_skip "jstest not installed"
fi

if ! lg_ui_available; then
    lg_pass "controller node $first present"
fi

if ! lg_ui_yesno "$info

Press and release every button, and move both sticks, over the next 8 seconds.
Start now and press OK."; then
    lg_skip "gamepad test cancelled"
fi

out="$LG_SESSION/jstest.log"
lg_try 12 jstest --event "$first" >"$out" 2>/dev/null
events=$(grep -c 'Event' "$out" 2>/dev/null)
case "$events" in '' | *[!0-9]*) events=0 ;; esac

info="$info
Events seen in 8 s: $events"

if [ "$events" -gt 0 ]; then
    if lg_ui_yesno "$info

Did every button and axis report correctly?"; then
        lg_pass "$first: $events input events"
    fi
    lg_warn "$first: $events events, but not all inputs confirmed"
fi

lg_ui_warn "$info

No input events arrived.  Check the cable or pairing and dmesg for 'input: ... joystick'."
lg_fail "$first produced no events"
