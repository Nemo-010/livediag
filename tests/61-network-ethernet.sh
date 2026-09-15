#!/bin/sh
# livediag: wired Ethernet link, carrier and DHCP.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-ethernet" "Ethernet" "Network"

wired=""
for i in $(lg_net_ifaces); do
    [ -d "/sys/class/net/$i/wireless" ] && continue
    t=$(cat "/sys/class/net/$i/type" 2>/dev/null)
    [ "$t" = "1" ] || continue
    wired="$wired $i"
done
[ -n "$wired" ] || lg_skip "no wired Ethernet interface detected"

wired=${wired# }
iface=$(printf '%s\n' $wired | head -n1)

carrier_file="/sys/class/net/$iface/carrier"
carrier=0
[ -r "$carrier_file" ] && carrier=$(cat "$carrier_file" 2>/dev/null)

if [ "$carrier" != "1" ] && lg_ui_available; then
    if lg_ui_yesno "Ethernet interface $iface has no link.

Plug a cable into your router or switch now, then press OK.  (Choose No to skip.)"; then
        i=0
        while [ "$i" -lt 20 ]; do
            carrier=$(cat "$carrier_file" 2>/dev/null)
            [ "$carrier" = "1" ] && break
            sleep 1
            i=$((i + 1))
        done
    fi
fi

if [ "$carrier" != "1" ]; then
    lg_ui_warn "No cable link on $iface.  The port or the cable may be at fault."
    lg_warn "$iface present but no carrier"
fi

speed=""
[ -r "/sys/class/net/$iface/speed" ] && speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null)

ip4=""
i=0
while [ "$i" -lt 20 ]; do
    ip4=$(lg_iface_ip4 "$iface")
    [ -n "$ip4" ] && break
    sleep 2
    i=$((i + 1))
done

if [ -z "$ip4" ] && lg_have udhcpc && lg_ui_available; then
    if lg_ui_yesno "$iface has a link but no IP address.

Try a DHCP request now with udhcpc?"; then
        lg_try 40 udhcpc -i "$iface" -q -n >/dev/null 2>&1
        ip4=$(lg_iface_ip4 "$iface")
    fi
fi

if [ -z "$ip4" ]; then
    lg_ui_warn "Interface $iface is up (link ${carrier}, speed ${speed:-?} Mb/s) but no IP address was obtained."
    lg_fail "$iface up but no address"
fi

gw=$(ip route 2>/dev/null | awk -v d="$iface" '$1=="default" && $5==d {print $3; exit}')

# Ping the gateway, then one resolver.
ping_target=${gw:-1.1.1.1}
if lg_ping "$ping_target" 1; then
    reach="gateway $ping_target reachable"
else
    reach="gateway $ping_target unreachable"
fi

lg_ui_info "Ethernet $iface
Address: $ip4
Link: ${carrier}  Speed: ${speed:-unknown} Mb/s
Gateway: ${gw:-unknown}
$reach"
lg_pass "$iface $ip4, link ${carrier}, ${speed:-?} Mb/s, $reach"
