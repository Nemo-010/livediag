#!/bin/sh
# livediag: battery presence, charge, health and discharge behaviour.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "power-battery" "Battery" "Power"

bat=""
for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    [ "$(cat "$d/type" 2>/dev/null)" = "Battery" ] || continue
    bat=${d##*/}
    break
done

if [ -z "$bat" ]; then
    lg_skip "no battery detected (desktop or always-on power)"
fi

p="/sys/class/power_supply/$bat"
get() { [ -r "$p/$1" ] && cat "$p/$1" 2>/dev/null; }

cap=$(get capacity)
status=$(get status)
health=$(get health)
cycles=$(get cycle_count)
voltage=$(get voltage_now)
full=$(get energy_full)
design=$(get energy_full_design)
[ -n "$full" ] || full=$(get charge_full)
[ -n "$design" ] || design=$(get charge_full_design)

health_pct=""
if [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ] 2>/dev/null; then
    health_pct=$(awk -v f="$full" -v d="$design" 'BEGIN { printf "%.0f", f * 100 / d }')
fi

info="Battery: $bat
Charge: ${cap:-?}%
Status: ${status:-?}
Health: ${health:-?}${health_pct:+ ($health_pct% of design)}
Cycles: ${cycles:-unknown}
Voltage: ${voltage:-?}"

unplugged=0
attempted=0
if lg_ui_available; then
    case "$status" in
    Charging | Full)
        if lg_ui_yesno "$info

Unplug the charger now, then press OK.  We will check that the battery takes over."; then
            attempted=1
            i=0
            while [ "$i" -lt 15 ]; do
                s=$(get status)
                case "$s" in
                Discharging | Not\ charging) unplugged=1; break ;;
                esac
                sleep 1
                i=$((i + 1))
            done
        fi
        ;;
    Discharging)
        if lg_ui_yesno "$info

Plug the charger in now, then press OK.  We will check that charging starts."; then
            attempted=1
            i=0
            while [ "$i" -lt 15 ]; do
                s=$(get status)
                case "$s" in
                Charging | Full) unplugged=1; break ;;
                esac
                sleep 1
                i=$((i + 1))
            done
        fi
        ;;
    esac
fi

if [ "$unplugged" = "1" ]; then
    info="$info
Power-path switch: observed"
elif [ "$status" = "Charging" ] || [ "$status" = "Full" ] || [ "$status" = "Discharging" ]; then
    info="$info
Power-path switch: not observed"
fi

if [ -n "$health_pct" ] && [ "$health_pct" -lt 80 ] 2>/dev/null; then
    lg_ui_warn "$info

Battery health is below 80% of its original capacity.  It still works, but runtime will be short."
    lg_warn "$bat ${cap:-?}% health ${health_pct}%"
fi

if [ "$attempted" = "1" ] && [ "$unplugged" = "0" ]; then
    case "$status" in
    Charging | Full | Discharging)
        lg_ui_warn "$info

The battery did not switch power source when you changed the charger.  The charging circuitry or cable may be at fault."
        lg_fail "$bat did not switch power state (status stayed ${status:-unknown})"
        ;;
    esac
fi

lg_ui_info "$info"
lg_pass "$bat ${cap:-?}%, status ${status:-?}${health_pct:+, health $health_pct%}"
