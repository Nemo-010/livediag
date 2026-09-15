#!/bin/sh
# livediag: default route, DNS and reachability of the wider Electrosphere.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-internet" "Connectivity" "Network"

iface=$(lg_default_iface)
ip4=""
[ -n "$iface" ] && ip4=$(lg_iface_ip4 "$iface")

nameservers=""
[ -r /etc/resolv.conf ] && nameservers=$(awk '/^nameserver/{printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)

info="Default interface: ${iface:-none}
Address: ${ip4:-none}
DNS servers: ${nameservers:-none}"

if [ -z "$iface" ]; then
    lg_ui_warn "$info

There is no default route, so nothing outside this machine can be reached.  Connect Wi-Fi or Ethernet first."
    lg_fail "no default route"
fi

# Name resolution, independent of raw reachability.
dns_ok=0
dns_detail="unavailable"
if lg_have getent; then
    dns_detail="getent"
    getent hosts www.google.com >/dev/null 2>&1 && dns_ok=1
elif lg_have nslookup; then
    dns_detail="nslookup"
    nslookup www.google.com >/dev/null 2>&1 && dns_ok=1
elif lg_have host; then
    dns_detail="host"
    host www.google.com >/dev/null 2>&1 && dns_ok=1
fi

probe_file="$LG_SESSION/internet-probe.txt"
lg_net_probe >"$probe_file" 2>&1
details=$(cat "$probe_file" 2>/dev/null)

http_ok=0
http_total=0
for u in "https://www.google.com/generate_204" "https://1.1.1.1/cdn-cgi/trace" "https://dns.google/resolve?name=example.com"; do
    http_total=$((http_total + 1))
    lg_http "$u" && http_ok=$((http_ok + 1))
done

info="$info
DNS via $dns_detail: $dns_ok
Raw probes: $LG_PROBE_OK/$LG_PROBE_TOTAL
HTTPS endpoints: $http_ok/$http_total"

if [ "$LG_PROBE_OK" -eq 0 ]; then
    lg_ui_warn "$info

$details

No resolver could be reached.  If you are on a captive portal, open a browser and accept its terms first."
    lg_fail "0/$LG_PROBE_TOTAL resolvers reachable"
fi

if [ "$dns_ok" = "0" ] && [ "$http_ok" -eq 0 ]; then
    lg_ui_warn "$info

$details

Raw IP traffic works but DNS and HTTPS do not.  Check /etc/resolv.conf and any proxy or captive portal."
    lg_warn "raw IP works, DNS/HTTPS fail"
fi

if command -v env >/dev/null 2>&1; then
    proxy="${HTTPS_PROXY:-${https_proxy:-}}"
    case "$proxy" in
    '') ;;
    *) info="$info
Proxy: $proxy" ;;
    esac
fi

lg_ui_info "$info

$details"
lg_pass "route via $iface, DNS $dns_ok, probes $LG_PROBE_OK/$LG_PROBE_TOTAL, HTTPS $http_ok/$http_total"
