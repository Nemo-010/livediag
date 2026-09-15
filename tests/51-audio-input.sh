#!/bin/sh
# livediag: microphone capture, silence check and playback.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "audio-input" "Microphone" "Audio"

found=""
if lg_have pactl; then
    found=$(pactl list short sources 2>/dev/null | awk '{print $2}' | grep -v monitor | head -n 3 | tr '\n' ' ')
fi
if [ -z "$found" ] && lg_have arecord; then
    found=$(arecord -l 2>/dev/null | awk -F': ' '/^card/{print $2}' | head -n 3 | tr '\n' ' ')
fi
if [ -z "$found" ] && [ -d /proc/asound ]; then
    found=$(awk '/^ *[0-9]+ \[/{print $2}' /proc/asound/cards 2>/dev/null | tr -d '[]' | tr '\n' ' ')
fi

if [ -z "$found" ]; then
    lg_skip "no capture device detected"
fi

if ! lg_ui_available; then
    lg_pass "capture device(s): $found"
fi

if ! lg_ui_yesno "Microphone test: $found

You will record about 4 seconds.  Say something, or tap the microphone, then we will play it back.
Continue?"; then
    lg_skip "microphone test cancelled"
fi

rec="$LG_SESSION/mic.wav"
ok=0
if lg_have arecord; then
    lg_try 15 arecord -q -f cd -d 4 "$rec" >/dev/null 2>&1 && ok=1
fi
if [ "$ok" = "0" ] && lg_have parecord; then
    lg_try 10 parecord --file-format=wav "$rec" >/dev/null 2>&1 && ok=1
fi
if [ "$ok" = "0" ] && lg_have pw-record; then
    lg_try 10 pw-record --format=s16 --rate=48000 --channels=1 "$rec" >/dev/null 2>&1 && ok=1
fi

if [ "$ok" = "0" ] || [ ! -s "$rec" ]; then
    lg_ui_warn "The microphone could not be recorded from.  Check the input source and its volume."
    lg_fail "recording failed ($found)"
fi

# Look for a signal instead of trusting a silent file.
peak=""
if lg_have ffmpeg; then
    peak=$(ffmpeg -i "$rec" -af volumedetect -f null - 2>&1 | awk -F: '/max_volume/{gsub(/ /,"",$2); print $2; exit}')
elif lg_have sox; then
    peak=$(sox "$rec" -n stat 2>&1 | awk -F: '/Maximum amplitude/{gsub(/ /,"",$2); print $2; exit}')
fi

silent=0
case "$peak" in
-*dB)
    db=${peak%dB}
    ok_db=$(awk -v v="$db" 'BEGIN { print (v < -50) ? 0 : 1 }')
    [ "$ok_db" = "0" ] && silent=1
    ;;
'') ;;
*)
    ok_amp=$(awk -v v="$peak" 'BEGIN { print (v < 0.001) ? 0 : 1 }')
    [ "$ok_amp" = "0" ] && silent=1
    ;;
esac

playback=0
if lg_play_wav "$rec"; then
    playback=1
fi

if [ "$silent" = "1" ]; then
    lg_ui_warn "The recording played back, but it is almost silent (peak $peak).  Check the microphone gain or mute switch."
    lg_warn "$found; recording is silent (peak ${peak:-unknown})"
fi

if [ "$playback" = "1" ] && lg_ui_yesno "Did you hear your own recording played back?"; then
    lg_pass "$found; captured and played back (peak ${peak:-unknown})"
fi

lg_warn "$found; recording captured but playback not confirmed"
