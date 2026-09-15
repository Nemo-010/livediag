#!/bin/sh
# livediag: speakers, headphones and channel balance.
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "audio-output" "Speakers" "Audio"

found=""
if lg_have pactl; then
    found=$(pactl list short sinks 2>/dev/null | awk '{print $2}' | head -n 3 | tr '\n' ' ')
fi
if [ -z "$found" ] && [ -d /proc/asound ]; then
    found=$(awk '/^ *[0-9]+ \[/{print $2}' /proc/asound/cards 2>/dev/null | tr -d '[]' | tr '\n' ' ')
fi
if [ -z "$found" ] && lg_have aplay; then
    found=$(aplay -l 2>/dev/null | awk -F': ' '/^card/{print $2}' | cut -d, -f1 | tr '\n' ' ')
fi

if [ -z "$found" ]; then
    lg_skip "no audio output device detected"
fi

mute=""
vol=""
if lg_have pactl; then
    mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')
    vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk -F/ '{print $2; exit}' | tr -d ' ')
fi

info="Output device(s): $found"
[ -n "$mute" ] && info="$info
Muted: $mute"
[ -n "$vol" ] && info="$info
Volume: $vol"

if [ "$mute" = "yes" ]; then
    lg_ui_warn "$info

The default output is muted.  Unmute it and run this test again."
    lg_warn "default sink is muted"
fi

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

A short tone will play twice: once through the left channel, once through the right.  Continue?"; then
    lg_skip "speaker test cancelled"
fi

out="$LG_SESSION/audio-output.log"
if lg_busy "Playing test tone..." "lg_play_tone" "$out"; then
    if lg_ui_yesno "Did you clearly hear a tone, first on one side and then the other?"; then
        heard=1
    else
        heard=0
    fi
else
    tail=$(tail -n 2 "$out" 2>/dev/null | tr '\n' ' ')
    lg_ui_warn "The test tone could not be played:
$tail"
    lg_warn "tone playback failed: $tail"
fi

if lg_ui_yesno "Optional: plug in headphones or external speakers.

Did the sound move to them automatically?"; then
    hp="headphones ok"
else
    hp="headphones not confirmed"
fi

if [ "$heard" = "1" ]; then
    lg_pass "$found; tone audible; $hp"
fi

lg_warn "$found; tone not heard; $hp"
