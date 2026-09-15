#!/bin/sh
# livediag: suspend to RAM (or freeze) and resume.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "power-suspend" "Suspend" "Power"

states=$(cat /sys/power/state 2>/dev/null)
mem_sleep=$(cat /sys/power/mem_sleep 2>/dev/null)

if [ -z "$states" ]; then
    lg_skip "kernel exposes no /sys/power/state (container or unsupported)"
fi

mode=""
case " $states " in
*" mem "*) mode=mem ;;
*" freeze "*) mode=freeze ;;
*" disk "*) mode=disk ;;
esac

if [ -z "$mode" ]; then
    lg_ui_warn "Supported sleep states: $states.  This machine cannot suspend."
    lg_skip "no suspend state available (states: $states)"
fi

if [ ! -w /sys/power/state ]; then
    lg_ui_warn "Suspend needs root.  Re-run livediag as root to test it."
    lg_skip "not permitted to write /sys/power/state"
fi

info="Supported states: $states
Memory sleep mode: ${mem_sleep:-unknown}
Chosen mode: $mode"

use_rtc=0
if [ "$mode" != "disk" ] && lg_have rtcwake && ls /dev/rtc* >/dev/null 2>&1; then
    use_rtc=1
fi

if ! lg_ui_available; then
    lg_skip "suspend test needs confirmation"
fi

if ! lg_ui_yesno "$info

The machine will sleep for about 12 seconds and should wake by itself.
Save your work first.

Continue?"; then
    lg_skip "suspend test cancelled"
fi

t0=$(date +%s)
resumed=0
if [ "$use_rtc" = "1" ]; then
    if lg_try 90 rtcwake -m "$mode" -s 12 >/dev/null 2>&1; then
        resumed=1
    fi
else
    # No RTC wake helper: suspend and rely on the user pressing the power
    # button.  This blocks until the system resumes.
    printf '%s\n' "$mode" >/sys/power/state 2>/dev/null && resumed=1
fi
t1=$(date +%s)
elapsed=$((t1 - t0))

if [ "$resumed" != "1" ]; then
    lg_ui_warn "The suspend request failed.  See dmesg for details."
    lg_fail "suspend did not complete"
fi

sleep 2
resume_log=$(dmesg 2>/dev/null | grep -iE 'PM: suspend (entry|exit)|ACPI: Low-level resume complete|PM: resume' | tail -n 4 | tr '\n' '; ')

info="$info
Elapsed: ${elapsed}s
Kernel: ${resume_log:-no resume messages found}"

if lg_have dmesg && dmesg 2>/dev/null | grep -iE 'PM:.*(error|failed)|ACPI Error.*resume' | grep -qiE 'error|fail'; then
    lg_ui_warn "$info

The kernel logged an error around the resume.  Check whether devices such as Wi-Fi or the touchpad came back."
    lg_warn "resumed but kernel logged errors: $resume_log"
fi

if lg_ui_yesno "$info

Did the machine wake up cleanly (screen, keyboard, network)?"; then
    lg_pass "suspended ($mode) and resumed in ${elapsed}s"
fi

lg_warn "resumed but the user reported problems ($mode, ${elapsed}s)"
