#!/bin/sh
# livediag: wall clock, timezone, hardware clock and NTP synchronisation.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "core-time" "Clock" "Core"

now=$(date 2>/dev/null)
utc=$(date -u 2>/dev/null)
year=$(date +%Y 2>/dev/null)
epoch=$(date +%s 2>/dev/null)

tz=""
[ -r /etc/timezone ] && tz=$(head -n1 /etc/timezone 2>/dev/null)
if [ -z "$tz" ]; then
    link=$(readlink -f /etc/localtime 2>/dev/null)
    case "$link" in
    */zoneinfo/*) tz=${link##*/zoneinfo/} ;;
    esac
fi
[ -n "$tz" ] || tz="${TZ:-unknown}"

rtc=""
if lg_have hwclock; then
    rtc=$(hwclock --show 2>/dev/null | sed 's/  */ /g')
fi
if [ -z "$rtc" ] && [ -r /sys/class/rtc/rtc0/date ]; then
    rtc="$(cat /sys/class/rtc/rtc0/date 2>/dev/null) $(cat /sys/class/rtc/rtc0/time 2>/dev/null)"
fi
[ -n "$rtc" ] || rtc="unavailable"

ntp=""
if lg_have timedatectl; then
    sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    [ -n "$sync" ] && ntp="synchronised=$sync"
fi
if [ -z "$ntp" ] && lg_have chronyc; then
    ntp=$(chronyc tracking 2>/dev/null | awk -F: '/Leap status/{gsub(/^ +/, "", $2); print $2; exit}')
    [ -n "$ntp" ] && ntp="chrony leap status=$ntp"
fi
if [ -z "$ntp" ] && lg_have ntpq; then
    if ntpq -p 2>/dev/null | grep -q '^\*'; then
        ntp="ntpd has a selected peer"
    fi
fi
if [ -z "$ntp" ]; then
    if { lg_have pgrep && pgrep -x chronyd >/dev/null 2>&1; } ||
        { lg_have pgrep && pgrep -x ntpd >/dev/null 2>&1; }; then
        ntp="daemon running, sync unknown"
    else
        ntp="no NTP daemon detected"
    fi
fi

info="Local time: $now ($tz)
UTC:        $utc
Unix epoch: $epoch
RTC:        $rtc
NTP:        $ntp"

sane=1
if [ -n "$year" ] && { [ "$year" -lt 2020 ] || [ "$year" -gt 2100 ]; }; then
    sane=0
fi

if [ "$sane" = "0" ]; then
    lg_ui_error "$info

The date is outside the expected range. A wrong clock breaks TLS, package managers and logins."
    lg_fail "clock reads $now, outside 2020-2100"
fi

if lg_ui_available; then
    if ! lg_ui_yesno "$info

Compare the local time above with your phone.  Does it match (within a minute or two)?"; then
        lg_ui_warn "Clock differs from your reference device.  Check the timezone and NTP before trusting anything else."
        lg_warn "time $now ($tz); user reported a mismatch; NTP: $ntp"
    fi
fi

lg_pass "$now ($tz); NTP: $ntp"
