#!/bin/sh
# livediag: mains/USB-C power supply detection and hotplug behaviour.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "power-ac" "Charger" "Power"

acs=""
for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    case "$(cat "$d/type" 2>/dev/null)" in
    Mains | USB | USB_CDP | USB_DCP | USB_ACA | USB_TYPE_C) acs="$acs ${d##*/}" ;;
    esac
done

typec=""
for d in /sys/class/typec/port*; do
    [ -e "$d" ] || continue
    typec="$typec ${d##*/}"
done

if [ -z "$acs" ] && [ -z "$typec" ]; then
    lg_skip "no AC/USB power supply detected"
fi

online_count() {
    n=0
    for a in $acs; do
        [ "$(cat "/sys/class/power_supply/$a/online" 2>/dev/null)" = "1" ] && n=$((n + 1))
    done
    printf '%s' "$n"
}

info="Power supplies:${acs:- none}"
for a in $acs; do
    info="$info
  $a: online=$(cat "/sys/class/power_supply/$a/online" 2>/dev/null)"
done
[ -n "$typec" ] && info="$info
USB-C ports:$typec"

online=$(online_count)

switched=0
attempted=0
if lg_ui_available && [ "$online" -gt 0 ]; then
    if lg_ui_yesno "$info

Unplug the power supply now, then press OK.  We will check that the hotplug event is seen."; then
        attempted=1
        i=0
        while [ "$i" -lt 15 ]; do
            [ "$(online_count)" -eq 0 ] && break
            sleep 1
            i=$((i + 1))
        done
        if lg_ui_yesno "Now plug the power supply back in, then press OK."; then
            i=0
            while [ "$i" -lt 15 ]; do
                [ "$(online_count)" -gt 0 ] && switched=1 && break
                sleep 1
                i=$((i + 1))
            done
        fi
    fi
fi

if [ "$attempted" = "1" ] && [ "$switched" = "0" ]; then
    lg_ui_warn "$info

The power supply state did not change when you unplugged and replugged it.  The connector, cable or EC may be at fault."
    lg_fail "no hotplug event observed on power supply"
fi

lg_ui_info "$info"
lg_pass "$(printf '%s' "${acs:-usb-c}") online=${online}"
