#!/bin/sh
# livediag: touchpad/mouse movement, dragging, scrolling and buttons.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "input-pointer" "Pointer" "Input"

pt=0
if [ -r /proc/bus/input/devices ]; then
    pt=$(awk '/^H: Handlers=/ && /mouse/ { c++ } END { print c + 0 }' /proc/bus/input/devices)
fi
if lg_have libinput; then
    lp=$(libinput list-devices 2>/dev/null | grep -c 'Capabilities:.*pointer' 2>/dev/null)
    [ "${lp:-0}" -gt "$pt" ] 2>/dev/null && pt=$lp
fi

if ! lg_ui_available; then
    lg_skip "pointer test needs the graphical session"
fi
if [ "$pt" -eq 0 ]; then
    lg_skip "no pointer device detected"
fi

if ! lg_ui_yesno "Pointer test.  You will need to:
  1. move the pointer and drag a slider,
  2. scroll with the wheel or two fingers,
  3. click left and right.

Continue?"; then
    lg_skip "pointer test cancelled"
fi

move_ok=0
val=$(zenity --scale --no-markup --title="$LIVEDIAG_TITLE" \
    --text="Drag the slider all the way to the right, then press OK." \
    --value=0 --min-value=0 --max-value=100 --step=1 2>/dev/null)
case "$val" in
'') move_ok=0 ;;
*) [ "$val" -ge 95 ] 2>/dev/null && move_ok=1 ;;
esac

scroll_ok=0
lg_ui_yesno "Scroll down and back up inside this window (wheel or two fingers).

Did the page scroll?" && scroll_ok=1

click_ok=0
lg_ui_yesno "Click somewhere with the LEFT button, then with the RIGHT button.

Did both clicks register?" && click_ok=1

info="Pointer devices: $pt
Move/drag: $move_ok
Scroll: $scroll_ok
Left/right click: $click_ok"

if [ "$move_ok" = "1" ] && [ "$scroll_ok" = "1" ] && [ "$click_ok" = "1" ]; then
    lg_ui_info "$info

Pointer works correctly."
    lg_pass "$pt pointer device(s), all interactions work"
elif [ "$move_ok" = "1" ]; then
    lg_ui_warn "$info

Basic movement works, but some gestures do not.  This is often just a missing touchpad driver or a setting."
    lg_warn "partial pointer: move=$move_ok scroll=$scroll_ok click=$click_ok"
fi

lg_fail "pointer did not pass (move=$move_ok scroll=$scroll_ok click=$click_ok)"
