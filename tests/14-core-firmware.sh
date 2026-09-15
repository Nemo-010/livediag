#!/bin/sh
# livediag: firmware mode, Secure Boot, TPM and whether the internal disk
# will actually be visible to a Linux installer.
#
# Everything here is read-only.  It exists because the things that most
# often stop an install are not broken hardware but firmware settings:
# Secure Boot refusing unsigned media, or an Intel RST/RAID disk that the
# installer simply cannot see.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "core-firmware" "Firmware" "Core"

fw="BIOS/legacy"
[ -d /sys/firmware/efi ] && fw="UEFI"

efi_secure="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
efi_setup="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

efi_byte() {
    [ -r "$1" ] || return 1
    od -An -tu1 "$1" 2>/dev/null | awk '{print $NF}'
}

secure="unknown"
b=$(efi_byte "$efi_secure") && case "$b" in
1) secure="on" ;;
0) secure="off" ;;
esac

setup="unknown"
b=$(efi_byte "$efi_setup") && case "$b" in
1) setup="setup mode (keys not enrolled)" ;;
0) setup="user mode" ;;
esac

tpm="no"
{ [ -e /sys/class/tpm/tpm0 ] || [ -e /sys/class/tpmrm/tpmrm0 ]; } && tpm="yes"

# Internal disks: block devices that are not removable and not USB.  The
# live stick itself is excluded because its path goes through the USB bus.
internal=""
for d in /sys/block/*; do
    [ -e "$d/device" ] || continue
    n=${d##*/}
    case "$n" in
    loop* | ram* | zram* | dm-* | md* | sr*) continue ;;
    esac
    [ "$(cat "$d/removable" 2>/dev/null)" = "1" ] && continue
    real=$(readlink -f "$d/device" 2>/dev/null)
    case "$real" in
    *"/usb"*) continue ;;
    esac
    internal="$internal $n"
done

windows="none"
bitlocker="no"
if lg_have blkid; then
    if blkid 2>/dev/null | grep -q 'TYPE="ntfs"'; then
        windows="NTFS volume present"
    fi
    if blkid 2>/dev/null | grep -qi 'BitLocker'; then
        bitlocker="yes"
    fi
fi

raid=""
if lg_have lspci; then
    raid=$(lspci 2>/dev/null | grep -Ei 'RAID bus controller|Volume Management Device' | head -n1)
fi

info="Firmware:      $fw
Secure Boot:   $secure
Setup mode:    $setup
TPM:           $tpm
Internal disk:${internal:- none}
Windows:       $windows
BitLocker:     $bitlocker"
[ -n "$raid" ] && info="$info
RAID controller: $raid"

warn=0
notes=""

if [ "$secure" = "on" ]; then
    warn=1
    notes="$notes
Secure Boot is on.  This test image is unsigned and will not boot with it
enabled; turn it off in the firmware setup, or use signed installation media."
fi

if [ "$fw" = "UEFI" ] && [ -z "$internal" ]; then
    warn=1
    notes="$notes
No internal disk is visible to Linux.${raid:+
A $raid is present: on many laptops the disk is set to RAID/Intel RST mode
and Linux cannot see it until the firmware is switched to AHCI.  Changing
that can make the existing Windows installation need a repair, so do it
deliberately.}"
fi

if [ "$bitlocker" = "yes" ]; then
    warn=1
    notes="$notes
A BitLocker volume was found.  Suspend or disable BitLocker in Windows first,
otherwise changing firmware or disk settings can lock Windows behind a
recovery key."
fi

if [ "$warn" = "1" ]; then
    lg_ui_warn "$info
$notes"
    lg_warn "firmware $fw; secure boot $secure; TPM $tpm; internal:${internal:- none}; windows $windows; bitlocker $bitlocker${raid:+; $raid}"
fi

lg_ui_info "$info

Nothing here was changed."
lg_pass "firmware $fw, secure boot $secure, TPM $tpm, disks:${internal:- none}"
