#!/bin/sh
# livediag: USB tethering (RNDIS / CDC-ECM / CDC-NCM) from a phone.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "network-rndis" "USB tethering" "Network"

usb_ifaces() {
    for i in $(lg_net_ifaces); do
        drv=$(readlink -f "/sys/class/net/$i/device/driver" 2>/dev/null)
        base=${drv##*/}
        case "$base" in
        rndis_host | cdc_ether | cdc_ncm | cdc_subset | usbnet | ax88179* | r8152* | r8153*)
            printf '%s\n' "$i"
            ;;
        esac
    done
}

have_mods=""
if lg_have modinfo; then
    for m in rndis_host cdc_ether cdc_ncm usbnet; do
        modinfo "$m" >/dev/null 2>&1 && have_mods="$have_mods $m"
    done
fi
for m in rndis_host cdc_ether cdc_ncm usbnet; do
    [ -d "/sys/module/$m" ] && case "$have_mods" in *"$m"*) ;; *) have_mods="$have_mods $m" ;; esac
done

before=$(usb_ifaces)
info="USB network interfaces now: ${before:-none}
Kernel support:$have_mods"

if [ -z "$before" ] && [ -z "$have_mods" ]; then
    lg_ui_warn "$info

The kernel has no RNDIS/CDC tethering modules at all.  This image cannot test USB tethering."
    lg_skip "no RNDIS/CDC modules available"
fi

if [ -z "$before" ]; then
    if ! lg_ui_available; then
        lg_skip "no USB network interface present"
    fi
    if ! lg_ui_yesno "$info

On your Android or iPhone:
  1. open the developer settings or the hotspot menu,
  2. turn on USB tethering,
  3. plug the phone into this machine.

Then press OK and we will watch for the new interface for up to 90 seconds."; then
        lg_skip "USB tethering test cancelled"
    fi
fi

iface=""
if [ -n "$before" ]; then
    # Tethering was already active; use the interface that is present.
    iface=$(printf '%s\n' $before | head -n1)
else
    i=0
    while [ "$i" -lt 45 ]; do
        iface=$(usb_ifaces | head -n1)
        [ -n "$iface" ] && break
        sleep 2
        i=$((i + 1))
    done
fi

if [ -z "$iface" ]; then
    lg_ui_warn "$info

No USB network interface appeared.  Check the cable (data cable, not charge-only), the phone's tethering setting, and dmesg for 'rndis_host' or 'cdc_ether'."
    lg_fail "no USB tethering interface appeared"
fi

ip4=""
i=0
while [ "$i" -lt 20 ]; do
    ip4=$(lg_iface_ip4 "$iface")
    [ -n "$ip4" ] && break
    sleep 2
    i=$((i + 1))
done

if [ -z "$ip4" ] && lg_have udhcpc && lg_ui_available; then
    if lg_ui_yesno "USB tethering interface $iface has no address.

Ask for a DHCP lease with udhcpc?"; then
        lg_try 40 udhcpc -i "$iface" -q -n >/dev/null 2>&1
        ip4=$(lg_iface_ip4 "$iface")
    fi
fi

if [ -z "$ip4" ]; then
    lg_ui_warn "USB interface $iface appeared but never received an address.  This often means tethering is not actually enabled on the phone."
    lg_fail "$iface present but no address"
fi

probe="$LG_SESSION/rndis-probe.txt"
lg_net_probe >"$probe" 2>&1
details=$(cat "$probe" 2>/dev/null)

if [ "$LG_PROBE_OK" -eq 0 ]; then
    lg_ui_warn "USB tethering gave $iface an address ($ip4) but nothing was reachable.
$details"
    lg_fail "$iface $ip4 but 0/$LG_PROBE_TOTAL probes"
fi

lg_ui_info "USB tethering works on $iface
Address: $ip4
Reachable: $LG_PROBE_OK/$LG_PROBE_TOTAL"
lg_pass "$iface $ip4, probes $LG_PROBE_OK/$LG_PROBE_TOTAL"
