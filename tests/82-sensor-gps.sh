#!/bin/sh
# livediag: GNSS/GPS receiver and position fix.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "sensor-gps" "GPS" "Sensors"

have_gpspipe=0
lg_have gpspipe && have_gpspipe=1
lg_have cgps && have_gpspipe=1

modem=""
if lg_have mmcli; then
    modem=$(lg_try 15 mmcli -L 2>/dev/null | grep -oE '/Modem/[0-9]+' | head -n1 | grep -oE '[0-9]+$')
fi

serial=""
for d in /dev/ttyUSB* /dev/ttyACM*; do
    [ -c "$d" ] || continue
    serial="$serial $d"
done

if [ "$have_gpspipe" = "0" ] && [ -z "$modem" ] && [ -z "$serial" ]; then
    lg_skip "no GPS receiver or GNSS-capable modem detected"
fi

info="gpsd tools: $have_gpspipe
GNSS modem: ${modem:-none}
Serial ports:${serial:- none}"

if [ -n "$modem" ]; then
    loc_status=$(lg_try 20 mmcli -m "$modem" --location-status 2>/dev/null | grep -iE 'gps|capabilit|enabled' | tr '\n' '; ')
    loc_get=$(lg_try 20 mmcli -m "$modem" --location-get 2>/dev/null)
    info="$info
Modem location: ${loc_status:-unknown}"
    lat=$(printf '%s\n' "$loc_get" | grep -oE '[0-9.-]+' | head -n1)
    lon=$(printf '%s\n' "$loc_get" | grep -oE '[0-9.-]+' | sed -n '2p')
    if [ -n "$lat" ] && [ -n "$lon" ]; then
        lg_pass "modem fix: $lat, $lon"
    fi
fi

if [ "$have_gpspipe" = "0" ]; then
    lg_ui_info "$info

No gpsd tools are installed; the GPS capability was reported only from the modem."
    lg_skip "no gpsd to read the receiver"
fi

if ! lg_ui_available; then
    lg_skip "GPS fix needs time; run interactively outdoors"
fi

if ! lg_ui_yesno "$info

GPS needs a clear view of the sky and can take up to a minute for a first fix.  We will listen for up to 70 seconds.
Start?"; then
    lg_skip "GPS test cancelled"
fi

raw="$LG_SESSION/gps.log"
lg_try 75 gpspipe -w -n 60 >"$raw" 2>/dev/null
tpv=$(grep '"class":"TPV"' "$raw" 2>/dev/null | tail -n1)
mode=$(printf '%s\n' "$tpv" | grep -oE '"mode":[0-9]+' | grep -oE '[0-9]+' | tail -n1)
lat=$(printf '%s\n' "$tpv" | grep -oE '"lat":-?[0-9.]+' | grep -oE '\-?[0-9.]+' | tail -n1)
lon=$(printf '%s\n' "$tpv" | grep -oE '"lon":-?[0-9.]+' | grep -oE '\-?[0-9.]+' | tail -n1)

info="$info
Last fix mode: ${mode:-none}
Position: ${lat:-?}, ${lon:-?}"

if [ -n "$mode" ] && [ "$mode" -ge 2 ] 2>/dev/null; then
    lg_pass "GPS fix: $lat, $lon (mode $mode)"
fi

lg_ui_warn "$info

No position fix was obtained.  This is normal indoors: GPS needs sky view."
lg_warn "GPS receiver present but no fix"
