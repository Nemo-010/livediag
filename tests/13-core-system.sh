#!/bin/sh
# livediag: DMI machine identity and form factor.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "core-system" "System" "Core"

dmi=/sys/class/dmi/id
[ -d "$dmi" ] || lg_skip "no DMI table (not x86/UEFI?)"

read_dmi() { cat "$dmi/$1" 2>/dev/null; }

vendor=$(read_dmi sys_vendor)
product=$(read_dmi product_name)
version=$(read_dmi product_version)
board=$(read_dmi board_name)
bios=$(read_dmi bios_version)
chassis=$(read_dmi chassis_type)

# SMBIOS chassis types: 8/9/10/11/14 are the portable ones.
case "$chassis" in
3 | 4 | 5 | 6 | 7) form="desktop" ;;
8 | 9 | 10 | 11 | 14) form="laptop" ;;
17) form="server" ;;
30 | 31 | 32) form="tablet or convertible" ;;
*) form="unknown" ;;
esac

battery=0
for b in /sys/class/power_supply/*; do
    [ -r "$b/type" ] || continue
    [ "$(cat "$b/type" 2>/dev/null)" = "Battery" ] && battery=1
done

info="Vendor:  ${vendor:-unknown}
Model:   ${product:-unknown} ${version:-}
Board:   ${board:-unknown}
BIOS:    ${bios:-unknown}
Chassis: ${chassis:-?} ($form)"

if [ "$form" = "laptop" ] && [ "$battery" = "0" ]; then
    info="$info
Note:    firmware says this is a portable machine, but no battery is visible."
fi

lg_ui_info "$info"
lg_pass "${vendor:-unknown} ${product:-unknown} (${form})"
