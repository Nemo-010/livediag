#!/bin/sh
# livediag: touchscreen tap and drag (phones, tablets, convertibles).
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "input-touch" "Touchscreen" "Input"

ts=0
if [ -r /proc/bus/input/devices ]; then
    ts=$(awk '/^N: Name=/ && tolower($0) ~ /touch/ { c++ } END { print c + 0 }' /proc/bus/input/devices)
fi
if lg_have libinput; then
    lt=$(libinput list-devices 2>/dev/null | grep -ci 'Capabilities:.*touch' 2>/dev/null)
    [ "${lt:-0}" -gt "$ts" ] 2>/dev/null && ts=$lt
fi

if [ "$ts" -eq 0 ]; then
    lg_skip "no touchscreen detected"
fi
if ! lg_ui_available; then
    lg_skip "touch test needs the graphical session"
fi

tap_ok=0
lg_ui_yesno "Touchscreen test.

Tap this window's OK button with your finger (not the mouse).

Did the button respond where you tapped?" && tap_ok=1

drag_ok=0
lg_ui_yesno "Now swipe up and down inside the window.

Did the content scroll smoothly and follow your finger?" && drag_ok=1

grab_ok=0
lg_ui_yesno "Finally, press and hold for a second, then drag.

Did the press-and-drag work?" && grab_ok=1

info="Touchscreen device(s): $ts
Tap: $tap_ok
Swipe/scroll: $drag_ok
Press-and-drag: $grab_ok"

if [ "$tap_ok" = "1" ] && [ "$drag_ok" = "1" ]; then
    lg_ui_info "$info

Touch input works.  (Multi-touch pinch gestures depend on the desktop and are not checked here.)"
    lg_pass "$ts touch device(s); tap and swipe work"
fi

lg_warn "touch input incomplete: tap=$tap_ok swipe=$drag_ok press-drag=$grab_ok"
