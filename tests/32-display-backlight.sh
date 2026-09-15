#!/bin/sh
# livediag: internal panel backlight range and interactive brightness control.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "display-backlight" "Backlight" "Display"

devices=""
for d in /sys/class/backlight/*; do
    [ -d "$d" ] || continue
    n=${d##*/}
    max=$(cat "$d/max_brightness" 2>/dev/null)
    case "$max" in '' | *[!0-9]*) continue ;; esac
    devices="$devices $n:$max"
done

if [ -z "$devices" ]; then
    lg_skip "no internal panel backlight (desktop or external monitor)"
fi

# Prefer the device with the widest range; that is normally the real panel
# rather than an ACPI video shim.
best=""
best_max=0
for item in $devices; do
    n=${item%%:*}
    m=${item##*:}
    if [ "$m" -gt "$best_max" ]; then
        best=$n
        best_max=$m
    fi
done

sys="/sys/class/backlight/$best"
cur=$(cat "$sys/brightness" 2>/dev/null)
cur_pct=$(awk -v c="${cur:-0}" -v m="$best_max" 'BEGIN { if (m > 0) printf "%d", c * 100 / m; else print 0 }')
original="${cur:-0}"

LG_CLEANUP_FN="lg_bl_restore"
lg_bl_restore() {
    if [ -w "$sys/brightness" ]; then
        printf '%s\n' "$original" >"$sys/brightness" 2>/dev/null
    elif lg_have brightnessctl; then
        lg_try 5 brightnessctl -d "$best" set "$original" >/dev/null 2>&1
    fi
}

lg_bl_set() {
    _pct=$1
    _val=$(awk -v p="$_pct" -v m="$best_max" 'BEGIN { v = p * m / 100; if (v < 1) v = 1; if (v > m) v = m; printf "%d", v }')
    if [ -w "$sys/brightness" ]; then
        printf '%s\n' "$_val" >"$sys/brightness" 2>/dev/null && return 0
    fi
    if lg_have brightnessctl; then
        lg_try 5 brightnessctl -d "$best" set "${_pct}%" >/dev/null 2>&1 && return 0
    fi
    return 1
}

info="Backlight device: $best
Current: $cur / $best_max ($cur_pct%)"

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

Test the brightness control?  A slider will appear; move it and watch the screen."; then
    lg_pass "$info; control test skipped"
fi

attempt=0
changed=0
while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    val=$(zenity --scale --no-markup --title="$LIVEDIAG_TITLE" \
        --text="Move the slider to change brightness, then press OK.\nAttempt $attempt of 3." \
        --value="$cur_pct" --min-value=1 --max-value=100 --step=1 2>/dev/null) || break
    case "$val" in '' | *[!0-9]*) break ;; esac
    if ! lg_bl_set "$val"; then
        lg_ui_warn "The backlight could not be changed.  On a live image this usually means the sysfs node is read-only; try running as root."
        lg_warn "$best not writable; current $cur/$best_max"
    fi
    cur_pct=$val
    if lg_ui_yesno "Did the screen brightness change?"; then
        changed=1
        break
    fi
done

lg_bl_restore
if [ "$changed" = "1" ]; then
    lg_pass "$best: brightness control works ($best_max steps)"
else
    lg_warn "$best: user could not observe a brightness change"
fi
