#!/bin/sh
# livediag: mobile broadband modem, SIM and registration.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-wwan" "Mobile broadband" "Network"

wwan_sys=""
for d in /sys/class/wwan*; do
    [ -e "$d" ] || continue
    wwan_sys="$wwan_sys ${d##*/}"
done

if [ -z "$wwan_sys" ] && ! lg_have mmcli; then
    lg_skip "no WWAN modem detected (and mmcli is not installed)"
fi

usb_modem=""
if lg_have lsusb; then
    usb_modem=$(lsusb 2>/dev/null | grep -iE 'modem|wwan|4G|LTE|5G' | head -n 2 | tr '\n' '; ')
fi

if ! lg_have mmcli; then
    lg_ui_warn "A WWAN device is present (${wwan_sys:-usb}) but ModemManager's mmcli is not installed, so it cannot be queried."
    lg_skip "WWAN present; mmcli unavailable"
fi

if lg_have rfkill; then
    rfkill unblock wwan >/dev/null 2>&1
fi

modems=$(lg_try 15 mmcli -L 2>/dev/null | grep -oE '/Modem/[0-9]+' | grep -oE '[0-9]+$' | tr '\n' ' ')
if [ -z "$modems" ]; then
    lg_ui_warn "ModemManager sees no modem.${wwan_sys:+ WWAN sysfs: $wwan_sys}${usb_modem:+ USB: $usb_modem}"
    lg_skip "no modem registered with ModemManager"
fi

info=""
bad=0
for n in $modems; do
    lg_try 15 mmcli -m "$n" --enable >/dev/null 2>&1
    m=$(lg_try 15 mmcli -m "$n" 2>/dev/null)
    state=$(printf '%s\n' "$m" | awk -F: '/State/{sub(/^ +/,"",$2); print $2; exit}')
    access=$(printf '%s\n' "$m" | awk -F: '/Access tech/{sub(/^ +/,"",$2); print $2; exit}')
    signal=$(printf '%s\n' "$m" | awk -F: '/Signal quality/{sub(/^ +/,"",$2); print $2; exit}')
    operator=$(printf '%s\n' "$m" | awk -F: '/operator name/{sub(/^ +/,"",$2); print $2; exit}')
    sim=$(printf '%s\n' "$m" | awk -F: '/Sim path|SIM path/{print $2; exit}')
    info="$info
Modem $n: state=${state:-unknown} operator=${operator:-?} access=${access:-?} signal=${signal:-?} sim=${sim:-none}"
    case "$state" in
    '' | disabled | failed | *failed*) bad=$((bad + 1)) ;;
    esac
    [ -z "$sim" ] && [ -z "$operator" ] && bad=$((bad + 1))
done

info="WWAN:${wwan_sys:- none}${usb_modem:+
USB: $usb_modem}$info"

if [ "$bad" -gt 0 ]; then
    lg_ui_warn "$info

A modem is present but is not registered or has no SIM.  Insert a data SIM and check the antenna."
    lg_warn "modem present but not usable: $info"
fi

lg_ui_info "$info"
lg_pass "$(printf '%s\n' $modems | wc -l | tr -d ' ') modem(s) enabled and registered"
