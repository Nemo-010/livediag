#!/bin/sh
# livediag: <one-line description of what this module checks>
#
# To add a module:
#   1. copy this file to tests/NN-category-name.sh
#   2. add one line to tests/tests.list
#   3. fill in the detection and the final result below
#
# Rules every module follows:
#   * never assume hardware is present - skip cleanly instead
#   * never assume a tool is installed - guard with lg_have
#   * ask before anything destructive, and say what it will touch
#   * finish with exactly one of lg_pass / lg_fail / lg_warn / lg_skip

LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "<id>" "<Name>" "<Category>"

# --- detect ----------------------------------------------------------------
if [ ! -e /sys/class/example ]; then
    lg_skip "no example hardware detected"
fi

info="Example device: /sys/class/example
Value: $(cat /sys/class/example/value 2>/dev/null)"

# --- interactive part (optional) -------------------------------------------
if lg_ui_available; then
    if ! lg_ui_yesno "$info

Run the interactive part?  It does <what, in plain words>."; then
        lg_pass "$info; interactive part skipped"
    fi
    result=$(lg_ui_input "Type the value shown on the device:") || lg_skip "cancelled"
    [ -n "$result" ] || lg_skip "empty answer"
    info="$info
You entered: $result"
fi

# --- result ----------------------------------------------------------------
lg_ui_info "$info"
lg_pass "$info"
