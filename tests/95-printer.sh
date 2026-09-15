#!/bin/sh
# livediag: CUPS printer queues and an optional test page.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "printer" "Printer" "Peripherals"

usb_printers=""
if lg_have lsusb; then
    usb_printers=$(lsusb 2>/dev/null | grep -iE 'printer|print' | head -n 3 | tr '\n' '; ')
fi

if ! lg_have lpstat; then
    if [ -n "$usb_printers" ]; then
        lg_ui_warn "Printer hardware is attached ($usb_printers) but the CUPS tools are not installed, so no queue can be tested."
        lg_skip "printer hardware present, CUPS missing"
    fi
    lg_skip "no CUPS client tools installed"
fi

status=$(lg_try 15 lpstat -p 2>&1)
printers=$(printf '%s\n' "$status" | awk '/printer/{print $2}' | tr '\n' ' ')
default=$(lg_try 10 lpstat -d 2>/dev/null | sed 's/.*: //')

if [ -z "$printers" ]; then
    if [ -n "$usb_printers" ]; then
        lg_ui_warn "A printer is attached ($usb_printers) but no CUPS queue is configured.  Add it in the printer settings first."
        lg_skip "printer attached but no queue"
    fi
    lg_ui_warn "CUPS is installed but reports no printers:
$status"
    lg_skip "no printer queues"
fi

info="Queues: $printers
Default: ${default:-none}
USB: ${usb_printers:-none}"

if ! lg_ui_available; then
    lg_pass "printer queue(s): $printers"
fi

target=$(printf '%s\n' $printers | head -n1)
if ! lg_ui_yesno "$info

Print a test page on '$target'?
Choose Yes only if the printer is loaded and you want to spend a sheet of paper."; then
    lg_pass "queue(s) present: $printers"
fi

page="/usr/share/cups/data/testprint"
if [ ! -r "$page" ]; then
    page="$LG_SESSION/testpage.txt"
    {
        printf 'livediag test page\n'
        printf 'queue: %s\n' "$target"
        printf 'date: %s\n' "$(date 2>/dev/null)"
    } >"$page"
fi

out="$LG_SESSION/print.log"
if lg_try 30 lp -d "$target" "$page" >"$out" 2>&1; then
    lg_ui_info "Job sent to '$target'.  Collect the page from the printer."
    if lg_ui_yesno "Did the page come out correctly?"; then
        lg_pass "printed a test page on $target"
    fi
    lg_warn "job accepted but the page did not print correctly"
fi

lg_ui_warn "Could not submit the job:
$(tail -n 2 "$out" 2>/dev/null | tr '\n' ' ')"
lg_fail "lp failed for $target"
