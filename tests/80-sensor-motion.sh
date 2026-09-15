#!/bin/sh
# livediag: accelerometer and gyroscope (phones, tablets, some laptops).
LG_TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$LG_TEST_DIR/../lib/common.sh"
lg_init
lg_begin "sensor-motion" "Motion" "Sensors"

accel=""
gyro=""
for d in /sys/bus/iio/devices/iio:device*; do
    [ -d "$d" ] || continue
    if [ -r "$d/in_accel_x_raw" ] && [ -z "$accel" ]; then
        accel=$d
    fi
    if [ -r "$d/in_anglvel_x_raw" ] && [ -z "$gyro" ]; then
        gyro=$d
    fi
done

if [ -z "$accel" ] && [ -z "$gyro" ]; then
    lg_skip "no accelerometer/gyroscope (iio) devices"
fi

read_vec() {
    d=$1
    x=$(cat "$d/in_accel_x_raw" 2>/dev/null)
    y=$(cat "$d/in_accel_y_raw" 2>/dev/null)
    z=$(cat "$d/in_accel_z_raw" 2>/dev/null)
    awk -v x="${x:-0}" -v y="${y:-0}" -v z="${z:-0}" \
        'BEGIN { printf "%.0f", (x < 0 ? -x : x) + (y < 0 ? -y : y) + (z < 0 ? -z : z) }'
}

before=""
[ -n "$accel" ] && before=$(read_vec "$accel")

info="Accelerometer: ${accel:-none}
Gyroscope: ${gyro:-none}"
[ -n "$before" ] && info="$info
Baseline magnitude: $before"

if [ -z "$accel" ]; then
    lg_pass "$info (gyroscope only; no interactive tilt test)"
fi

if ! lg_ui_available; then
    lg_pass "$info"
fi

if ! lg_ui_yesno "$info

Pick the device up and tilt it slowly in each direction, then put it down.
Press OK when you have finished moving it."; then
    lg_skip "motion test cancelled"
fi

after=$(read_vec "$accel")
delta=$((after - before))
[ "$delta" -lt 0 ] && delta=$((-delta))

info="$info
After tilt: $after (change $delta)"

if [ "$delta" -gt 20 ]; then
    lg_pass "$info"
fi

lg_ui_warn "$info

The accelerometer reading barely changed.  Either the sensor is not wired to the kernel or it was not moved."
lg_warn "accelerometer unchanged (delta $delta)"
