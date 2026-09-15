#!/bin/sh
# livediag: temperatures, fans and behaviour under load.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "thermal" "Temperatures" "Thermal"

max_temp=0
max_src=""
list=""

scan_temps() {
    for z in /sys/class/thermal/thermal_zone*; do
        [ -r "$z/temp" ] || continue
        t=$(cat "$z/temp" 2>/dev/null)
        case "$t" in '' | *[!0-9-]*) continue ;; esac
        c=$((t / 1000))
        type=$(cat "$z/type" 2>/dev/null)
        printf '  zone %-20s %s C\n' "${type:-$z}" "$c"
    done
    for h in /sys/class/hwmon/hwmon*; do
        [ -d "$h" ] || continue
        hname=$(cat "$h/name" 2>/dev/null)
        for f in "$h"/temp*_input; do
            [ -r "$f" ] || continue
            t=$(cat "$f" 2>/dev/null)
            case "$t" in '' | *[!0-9-]*) continue ;; esac
            c=$((t / 1000))
            label=$(cat "${f%_input}_label" 2>/dev/null)
            printf '  %-10s %-14s %s C\n' "$hname" "${label:-temp}" "$c"
        done
    done
}

max_of() {
    m=0
    for z in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$z" ] || continue
        t=$(cat "$z" 2>/dev/null)
        case "$t" in '' | *[!0-9-]*) continue ;; esac
        c=$((t / 1000))
        [ "$c" -gt "$m" ] && m=$c
    done
    for f in /sys/class/hwmon/hwmon*/temp*_input; do
        [ -r "$f" ] || continue
        t=$(cat "$f" 2>/dev/null)
        case "$t" in '' | *[!0-9-]*) continue ;; esac
        c=$((t / 1000))
        [ "$c" -gt "$m" ] && m=$c
    done
    printf '%s' "$m"
}

list=$(scan_temps)
if [ -z "$list" ]; then
    lg_skip "no temperature sensors found"
fi

fans=""
for f in /sys/class/hwmon/hwmon*/fan*_input; do
    [ -r "$f" ] || continue
    label=$(cat "${f%_input}_label" 2>/dev/null)
    fans="$fans
  ${label:-fan}: $(cat "$f" 2>/dev/null) rpm"
done
if [ -n "$fans" ]; then
    list="$list
Fans:$fans"
elif lg_have sensors; then
    sens=$(sensors 2>/dev/null)
    case "$sens" in *fan*) list="$list
$sens" ;; esac
fi

critical=0
for t in /sys/class/thermal/thermal_zone*/trip_point_*_temp; do
    [ -r "$t" ] || continue
    v=$(cat "$t" 2>/dev/null)
    case "$v" in '' | *[!0-9-]*) continue ;; esac
    [ "$v" -gt "$critical" ] && critical=$v
done
[ "$critical" -gt 0 ] 2>/dev/null && critical=$((critical / 1000))

idle=$(max_of)

loaded=$idle
if lg_ui_available; then
    if lg_ui_yesno "$list

Idle maximum: ${idle} C

Put the CPU under load for about 8 seconds to test cooling?
(This is safe; it is the same as opening a heavy application.)"; then
        out="$LG_SESSION/thermal-load.log"
        lg_busy "Loading all CPUs for 8 seconds..." '
            n=$(lg_ncpu)
            i=0
            while [ "$i" -lt "$n" ]; do
                (
                    end=$(( $(date +%s) + 8 ))
                    while [ "$(date +%s)" -lt "$end" ]; do
                        awk "BEGIN { for (j = 0; j < 40000; j++) x = j }"
                    done
                ) &
                i=$((i + 1))
            done
            wait' "$out" >/dev/null 2>&1
        loaded=$(max_of)
        list="$list
Under load: ${loaded} C"
    fi
else
    loaded=$idle
fi

info="$list

Idle max: ${idle} C
Load max: ${loaded} C${critical:+, critical trip $critical C}"

if dmesg 2>/dev/null | grep -qiE 'thermal.*(throttl|shutdown)|CPU[0-9]+: Core temperature above'; then
    lg_ui_warn "$info

The kernel log shows thermal throttling or a shutdown trip.  Clean the fan and vents."
    lg_warn "thermal throttling seen; idle ${idle} C load ${loaded} C"
fi

if [ "$loaded" -ge 95 ] 2>/dev/null; then
    lg_ui_warn "$info

Temperatures reached ${loaded} C under load.  This is close to the limit."
    lg_warn "high load temperature ${loaded} C"
fi

if [ "$critical" -gt 0 ] 2>/dev/null && [ "$loaded" -ge "$critical" ]; then
    lg_fail "temperature ${loaded} C reached the critical trip of ${critical} C"
fi

lg_ui_info "$info"
lg_pass "idle ${idle} C, load ${loaded} C, ${critical:-?} C trip"
