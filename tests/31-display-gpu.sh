#!/bin/sh
# livediag: GPU driver, kernel nodes, OpenGL/Vulkan and 3D acceleration.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "display-gpu" "GPU" "Display"

gpus=""
drivers=""
if lg_have lspci; then
    gpus=$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' | sed 's/^[0-9a-f.:]* //')
    drivers=$(lspci -k 2>/dev/null | awk '/VGA compatible controller|3D controller|Display controller/{f=1} f&&/Kernel driver in use/{sub(/.*: /,""); print; f=0}')
fi

# Fall back to the DRM subsystem when lspci is absent.
if [ -z "$gpus" ]; then
    for d in /sys/class/drm/card[0-9]*; do
        [ -e "$d/device" ] || continue
        gpus="$gpus
$(basename "$d")"
    done
fi

render_nodes=$(ls /dev/dri/renderD* 2>/dev/null | tr '\n' ' ')
info="GPU: ${gpus:-none detected}
Kernel drivers: ${drivers:-unknown}
DRM nodes: ${render_nodes:-none}"

accel="unknown"
if [ -n "${DISPLAY:-}" ] && lg_have glxinfo; then
    gl=$(lg_try 20 glxinfo -B 2>/dev/null)
    renderer=$(printf '%s\n' "$gl" | awk -F: '/OpenGL renderer string/{sub(/^ /,"",$2); print $2; exit}')
    direct=$(printf '%s\n' "$gl" | awk -F: '/direct rendering/{sub(/^ /,"",$2); print $2; exit}')
    info="$info
OpenGL renderer: ${renderer:-unknown}
Direct rendering: ${direct:-unknown}"
    case "$renderer" in
    *llvmpipe* | *softpipe* | *swrast* | *Software*) accel="software" ;;
    '') ;;
    *) [ "${direct:-yes}" = "Yes" ] && accel="hardware" || accel="software" ;;
    esac
elif [ -n "$render_nodes" ]; then
    accel="present"
fi

if lg_have vulkaninfo; then
    vk=$(lg_try 25 vulkaninfo --summary 2>/dev/null | awk -F= '
        /deviceName/ { gsub(/^[ \t]+|,/,"",$2); print "Vulkan device: " $2; exit }')
    [ -n "$vk" ] && info="$info
$vk"
fi

case "$accel" in
software)
    lg_ui_warn "$info

The desktop is rendering in software.  Everything works, but video playback and 3D games will be slow.  A GPU driver may be missing."
    lg_warn "software rendering; GPU: ${gpus:-none}"
    ;;
unknown)
    if [ -z "$render_nodes" ]; then
        lg_ui_warn "$info

A GPU is present but the kernel exposes no /dev/dri render node.  The driver is probably missing or not loaded."
        lg_warn "GPU without a DRM render node: ${gpus:-?}"
    fi
    ;;
esac

lg_ui_info "$info"
lg_pass "acceleration: $accel"
