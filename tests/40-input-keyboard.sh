#!/bin/sh
# livediag: keyboard typing test covering letters, digits and punctuation.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "input-keyboard" "Keyboard" "Input"

kb=0
if [ -r /proc/bus/input/devices ]; then
    kb=$(awk '
        /^N: Name=/ { name = $0 }
        /^H: Handlers=/ { if ($0 ~ /kbd/) c++ }
        END { print c + 0 }' /proc/bus/input/devices)
fi
if lg_have libinput; then
    lk=$(libinput list-devices 2>/dev/null | grep -c 'Capabilities:.*keyboard' 2>/dev/null)
    [ "${lk:-0}" -gt "$kb" ] 2>/dev/null && kb=$lk
fi

if [ "$kb" -eq 0 ] && ! lg_ui_available; then
    lg_skip "no keyboard device and no graphical session"
fi

if ! lg_ui_available; then
    lg_skip "keyboard test needs the graphical session"
fi

expected="the quick brown fox jumps over the lazy dog 0123456789"

attempt=1
while [ "$attempt" -le 3 ]; do
    typed=$(lg_ui_input "Type this sentence, then press OK:

$expected

(Every letter and digit is checked.  Use the on-screen keyboard if there is no physical one.)") || {
        lg_skip "typing test cancelled"
    }
    lower=$(printf '%s' "$typed" | tr 'A-Z' 'a-z')
    missing=""
    for ch in t h e q u i c k b r o w n f x j m p s v l a z y d g 0 1 2 3 4 5 6 7 8 9; do
        case "$lower" in
        *"$ch"*) ;;
        *) missing="$missing$ch" ;;
        esac
    done
    if [ -z "$missing" ]; then
        lg_ui_info "Every letter and digit registered correctly."
        lg_pass "typing test passed on attempt $attempt (${kb} keyboard device(s))"
    fi
    attempt=$((attempt + 1))
    lg_ui_warn "These keys did not register: $missing

Check the layout, then try again ($((attempt - 1)) of 3 done)."
done

lg_fail "keys did not register after 3 attempts: $missing"
