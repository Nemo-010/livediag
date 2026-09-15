#!/bin/sh
# livediag: connected displays, connectors and current resolution.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "display-output" "Output" "Display"

session="${XDG_SESSION_TYPE:-}"
[ -n "$session" ] || {
    [ -n "${WAYLAND_DISPLAY:-}" ] && session=wayland
}
[ -n "$session" ] || {
    [ -n "${DISPLAY:-}" ] && session=x11
}
[ -n "$session" ] || session=none

info="Session: ${session}"

# DRM connectors are visible from the kernel even without a display server.
connected=0
for s in /sys/class/drm/card*-*/status; do
    [ -r "$s" ] || continue
    st=$(cat "$s" 2>/dev/null)
    name=${s%/status}
    name=${name##*/}
    case "$name" in *-*) ;; *) continue ;; esac
    [ "$st" = "connected" ] && connected=$((connected + 1))
done
info="$info
Kernel reports $connected connected connector(s)"

xr=""
if [ -n "${DISPLAY:-}" ] && lg_have xrandr; then
    xr=$(lg_try 10 xrandr --query 2>/dev/null)
fi

if [ -n "$xr" ]; then
    modes=$(printf '%s\n' "$xr" | awk '
        /^[A-Za-z0-9._-]+ (connected|disconnected)/ { out = out "\n" $0; next }
        /^[[:space:]]+[0-9]+x[0-9]+/ { if (++n <= 3) out = out "\n    " $1 " " $2 }
        END { print out }')
    info="$info
xrandr:$modes"
elif [ -n "${WAYLAND_DISPLAY:-}" ] && lg_have wlr-randr; then
    info="$info
$(lg_try 10 wlr-randr 2>/dev/null)"
fi

if [ "$connected" -eq 0 ] && [ -z "$xr" ]; then
    lg_ui_warn "$info

No connected display was detected.  If you are looking at a screen right now, the kernel output may be behind a virtual terminal."
    lg_warn "no connected connector detected"
fi

lg_ui_info "$info"
if lg_ui_available; then
    if ! lg_ui_yesno "$info

Is the picture on every attached screen sharp, correctly sized and free of flicker or colour banding?"; then
        lg_ui_warn "Display problem reported by the user."
        lg_warn "user reported a display problem"
    fi
fi

lg_pass "$connected connected connector(s); session $session"
