#!/bin/sh
# livediag: webcam detection, frame capture and preview.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "video-camera" "Camera" "Video"

devs=""
for d in /dev/video*; do
    [ -c "$d" ] || continue
    devs="$devs $d"
done

if [ -z "$devs" ]; then
    lg_skip "no /dev/video* capture device found"
fi

names=""
if lg_have v4l2-ctl; then
    names=$(lg_try 10 v4l2-ctl --list-devices 2>/dev/null | sed 's/^[[:space:]]*//' | grep -v '^/dev/' | grep -v '^$' | head -n 4 | tr '\n' '; ')
fi

info="Capture devices: $devs"
[ -n "$names" ] && info="$info
Names: $names"

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

A single frame will be captured and shown.  Make sure the privacy shutter is open.
Continue?"; then
    lg_skip "camera test cancelled"
fi

img="$LG_SESSION/camera.jpg"
captured=0
for d in $devs; do
    if lg_have ffmpeg; then
        if lg_try 20 ffmpeg -y -loglevel error -f v4l2 -i "$d" -frames:v 1 -q:v 3 "$img" >/dev/null 2>&1 &&
            [ -s "$img" ]; then
            captured=1
            used=$d
            break
        fi
    fi
    if [ "$captured" = "0" ] && lg_have fswebcam; then
        if lg_try 20 fswebcam -q -d "$d" -r 640x480 --no-banner "$img" >/dev/null 2>&1 &&
            [ -s "$img" ]; then
            captured=1
            used=$d
            break
        fi
    fi
done

if [ "$captured" = "0" ]; then
    lg_ui_warn "$info

The camera device exists but no frame could be captured.  The kernel module may be missing, or another program may be using it."
    lg_fail "capture failed on$devs"
fi

lg_ui_info "A frame was captured from $used.  It will open in a viewer now; close the viewer when you are done."

shown=0
if lg_have feh; then
    feh -F "$img" >/dev/null 2>&1 && shown=1
elif lg_have eog; then
    eog "$img" >/dev/null 2>&1 && shown=1
elif lg_have mpv; then
    mpv --fullscreen --really-quiet --image-display-duration=6 "$img" >/dev/null 2>&1 && shown=1
elif lg_have xdg-open; then
    xdg-open "$img" >/dev/null 2>&1 && shown=1
fi

if [ "$shown" = "0" ]; then
    lg_ui_info "No image viewer was available.  The frame is saved at:
$img"
fi

if lg_ui_yesno "Did the captured image show a clear picture (not black, not scrambled)?"; then
    lg_pass "$used captured a usable frame"
fi

lg_warn "$used captured a frame but the user reported a problem"
