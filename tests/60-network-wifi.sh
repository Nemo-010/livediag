#!/bin/sh
# livediag: Wi-Fi scan, connect to a hotspot and verify the link end to end.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-wifi" "Wi-Fi" "Network"

wifi=""
for i in $(lg_net_ifaces); do
    lg_is_wireless "$i" && wifi="$wifi $i"
done
[ -n "$wifi" ] || lg_skip "no wireless interface detected"

wifi=${wifi# }
iface=$(printf '%s\n' $wifi | head -n1)

if lg_have rfkill; then
    rfkill unblock wifi >/dev/null 2>&1
fi

backend=none
if lg_have nmcli; then
    backend=nmcli
elif lg_have iwctl; then
    backend=iwctl
elif lg_have wpa_cli; then
    backend=wpa_cli
fi

scan="$LG_SESSION/wifi-scan.txt"
: >"$scan"
case "$backend" in
nmcli)
    lg_try 30 nmcli -t -f SSID,SIGNAL,SECURITY device wifi list >"$scan" 2>/dev/null
    ;;
iwctl)
    lg_try 30 iwctl station "$iface" scan >/dev/null 2>&1
    sleep 2
    lg_try 30 iwctl station "$iface" get-networks >"$scan" 2>/dev/null
    ;;
wpa_cli)
    lg_try 30 wpa_cli -i "$iface" scan >/dev/null 2>&1
    sleep 3
    lg_try 30 wpa_cli -i "$iface" scan_results >"$scan" 2>/dev/null
    ;;
*)
    if lg_have iw; then
        lg_try 30 iw dev "$iface" scan >"$scan" 2>/dev/null
    fi
    ;;
esac

nets=$(grep -viE '^$|signal|bssid|address' "$scan" 2>/dev/null | head -n 15 | tr '\n' '; ')

info="Wireless interface: $iface
Backend: $backend
Visible networks: ${nets:-none (scan unavailable)}"

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

To test Wi-Fi properly, enable a mobile hotspot on your phone (2.4 GHz if possible) and keep it close.
Then press OK and enter its name and password."; then
    lg_skip "Wi-Fi connect test cancelled"
fi

ssid=$(lg_ui_input "Hotspot name (SSID):") || lg_skip "no SSID entered"
[ -n "$ssid" ] || lg_skip "empty SSID"

pw=""
if lg_ui_yesno "Is this hotspot password protected?"; then
    pw=$(lg_ui_password "Wi-Fi password for '$ssid':") || lg_skip "password entry cancelled"
fi

iface=${iface:-$(printf '%s\n' $wifi | head -n1)}
log="$LG_SESSION/wifi-connect.log"
: >"$log"
connected=0

case "$backend" in
nmcli)
    if [ -n "$pw" ]; then
        if printf '%s\n' "$pw" | lg_try 90 nmcli --ask device wifi connect "$ssid" >"$log" 2>&1; then
            connected=1
        elif lg_try 90 nmcli device wifi connect "$ssid" password "$pw" >>"$log" 2>&1; then
            connected=1
        fi
    else
        lg_try 90 nmcli device wifi connect "$ssid" >>"$log" 2>&1 && connected=1
    fi
    ;;
iwctl)
    if [ -n "$pw" ]; then
        lg_try 90 iwctl station "$iface" connect "$ssid" --passphrase="$pw" >>"$log" 2>&1 && connected=1
    else
        lg_try 90 iwctl station "$iface" connect "$ssid" >>"$log" 2>&1 && connected=1
    fi
    ;;
wpa_cli)
    id=$(lg_try 10 wpa_cli -i "$iface" add_network 2>/dev/null | tail -n1)
    case "$id" in
    '' | *[!0-9]*)
        lg_ui_warn "wpa_cli could not create a network entry."
        lg_fail "wpa_cli add_network failed"
        ;;
    esac
    lg_try 10 wpa_cli -i "$iface" set_network "$id" ssid "\"$ssid\"" >>"$log" 2>&1
    [ -n "$pw" ] && lg_try 10 wpa_cli -i "$iface" set_network "$id" psk "\"$pw\"" >>"$log" 2>&1
    lg_try 10 wpa_cli -i "$iface" enable_network "$id" >>"$log" 2>&1
    lg_try 10 wpa_cli -i "$iface" select_network "$id" >>"$log" 2>&1
    lg_try 10 wpa_cli -i "$iface" save_config >/dev/null 2>&1
    connected=1
    ;;
*)
    lg_ui_warn "No supported Wi-Fi manager (nmcli, iwctl or wpa_cli) was found, so livediag cannot connect for you.  Use the desktop's network applet, then re-run this test."
    lg_skip "$iface present; no manager to drive it"
    ;;
esac

if [ "$connected" != "1" ]; then
    tail=$(tail -n 3 "$log" 2>/dev/null | tr '\n' ' ')
    lg_ui_warn "Could not join '$ssid'.  Check the name, password and that the hotspot is in range.
$tail"
    lg_fail "join '$ssid' failed: $tail"
fi

# Wait for an address to appear.
ip4=""
i=0
while [ "$i" -lt 30 ]; do
    ip4=$(lg_iface_ip4 "$iface")
    [ -n "$ip4" ] && break
    sleep 2
    i=$((i + 1))
done

if [ -z "$ip4" ]; then
    lg_ui_warn "Joined '$ssid' but no IP address arrived on $iface.  The hotspot may not be sharing its connection."
    lg_fail "no DHCP lease on $iface after joining '$ssid'"
fi

probe="$LG_SESSION/wifi-probe.txt"
lg_net_probe >"$probe" 2>&1
tail=$(cat "$probe" 2>/dev/null)

signal=""
if lg_have iw; then
    signal=$(lg_try 10 iw dev "$iface" link 2>/dev/null | awk -F: '/signal/{gsub(/ /,"",$2); print $2; exit}')
fi

if [ "$LG_PROBE_OK" -eq 0 ]; then
    lg_ui_warn "Connected to '$ssid' at $ip4 but no server answered.
$tail"
    lg_fail "connected to '$ssid' but 0/$LG_PROBE_TOTAL probes succeeded"
fi

lg_ui_info "Wi-Fi connected to '$ssid'
Address: $ip4
Signal: ${signal:-unknown}
Reachable: $LG_PROBE_OK/$LG_PROBE_TOTAL resolvers"
lg_pass "joined '$ssid' on $iface, $ip4, ${signal:-?}, probes $LG_PROBE_OK/$LG_PROBE_TOTAL"
