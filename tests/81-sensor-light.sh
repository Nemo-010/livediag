#!/bin/sh
# livediag: ambient light and proximity sensors.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "sensor-light" "Light" "Sensors"

illum=""
prox=""
for d in /sys/bus/iio/devices/iio:device*; do
    [ -d "$d" ] || continue
    if [ -z "$illum" ] && { [ -r "$d/in_illuminance_input" ] || [ -r "$d/in_intensity_both_raw" ]; }; then
        illum=$d
    fi
    if [ -z "$prox" ] && [ -r "$d/in_proximity_raw" ]; then
        prox=$d
    fi
done

if [ -z "$illum" ] && [ -z "$prox" ]; then
    lg_skip "no ambient light / proximity sensor"
fi

read_lux() {
    for f in "$1/in_illuminance_input" "$1/in_intensity_both_raw" "$1/in_intensity_raw"; do
        [ -r "$f" ] && cat "$f" 2>/dev/null && return 0
    done
    printf '0'
}

read_prox() {
    [ -r "$1/in_proximity_raw" ] && cat "$1/in_proximity_raw" 2>/dev/null || printf '0'
}

info="Light sensor: ${illum:-none}
Proximity sensor: ${prox:-none}"
[ -n "$illum" ] && info="$info
Ambient level now: $(read_lux "$illum")"
[ -n "$prox" ] && info="$info
Proximity now: $(read_prox "$prox")"

if ! lg_ui_available; then
    lg_pass "$info"
fi

changed=0
if [ -n "$illum" ]; then
    before=$(read_lux "$illum")
    if lg_ui_yesno "$info

Cover the light sensor with your hand or a finger, then press OK."; then
        after=$(read_lux "$illum")
        delta=$((after - before))
        [ "$delta" -lt 0 ] && delta=$((-delta))
        info="$info
After covering: $after (change $delta)"
        [ "$delta" -gt 5 ] && changed=1
        [ "$before" -eq 0 ] && [ "$after" -gt 0 ] && changed=1
    fi
fi

if [ -n "$prox" ] && [ "$changed" = "0" ]; then
    before=$(read_prox "$prox")
    if lg_ui_yesno "$info

Move your hand close to the screen (over the proximity sensor), then press OK."; then
        after=$(read_prox "$prox")
        [ "$after" != "$before" ] && changed=1
        info="$info
Proximity after: $after"
    fi
fi

if [ "$changed" = "1" ]; then
    lg_pass "sensor readings responded to a physical change"
fi

lg_ui_warn "$info

The readings did not respond.  On many laptops the light/proximity sensor is optional or not exposed to Linux."
lg_warn "no sensor response observed"
