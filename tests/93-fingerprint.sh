#!/bin/sh
# livediag: fingerprint reader detection and verification.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "fingerprint" "Fingerprint" "Peripherals"

usb_fp=""
if lg_have lsusb; then
    usb_fp=$(lsusb 2>/dev/null | grep -i 'finger' | head -n1)
fi
if [ -z "$usb_fp" ]; then
    for p in /sys/bus/usb/devices/*/product; do
        [ -r "$p" ] || continue
        if grep -qi 'finger' "$p" 2>/dev/null; then
            usb_fp="$usb_fp $(cat "$p")"
        fi
    done
fi

fprintd=0
lg_have fprintd-verify && fprintd=1

if [ -z "$usb_fp" ] && [ "$fprintd" = "0" ]; then
    lg_skip "no fingerprint reader detected"
fi

if [ "$fprintd" = "0" ]; then
    lg_ui_warn "Fingerprint hardware found (${usb_fp:-unknown}) but fprintd is not installed, so it cannot be driven."
    lg_skip "reader present, fprintd missing"
fi

user=$(id -un 2>/dev/null)
enrolled=$(lg_try 15 fprintd-list "$user" 2>/dev/null)
info="Reader: ${usb_fp:-unknown}
User: $user
Enrolled: $(printf '%s\n' "$enrolled" | grep -c 'finger' 2>/dev/null)"

if printf '%s\n' "$enrolled" | grep -qi 'no devices\|not found'; then
    lg_ui_warn "A fingerprint reader is present but libfprint has no driver for it, so it cannot be used."
    lg_skip "reader present but unsupported by libfprint"
fi

if ! printf '%s\n' "$enrolled" | grep -qi 'finger'; then
    lg_ui_info "No fingerprint is enrolled for $user.

Enrol one from a terminal with:  fprintd-enroll $user"
    lg_skip "no enrolled fingerprint"
fi

if ! lg_ui_available; then
    lg_pass "fingerprint enrolled; verification needs interaction"
fi

if lg_ui_yesno "$info

Swipe your enrolled finger when prompted.  Continue?"; then
    out="$LG_SESSION/fprint.log"
    if lg_try 40 fprintd-verify "$user" >"$out" 2>&1; then
        lg_ui_info "Fingerprint verified."
        lg_pass "fingerprint verified for $user"
    fi
    tail=$(tail -n 3 "$out" 2>/dev/null | tr '\n' ' ')
    lg_ui_warn "Fingerprint verification failed:
$tail"
    lg_fail "fprintd-verify failed: $tail"
fi

lg_skip "fingerprint test cancelled"
