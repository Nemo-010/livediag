# livediag

Live system diagnostics for a Linux install party.

`livediag` is a small, self-contained suite of shell modules that walk a
person through checking the things they actually use on a computer - Wi-Fi,
Bluetooth, sound, the keyboard, the battery, cameras and so on - then writes a
plain report.  The point is to boot a live image and find out whether this
machine is happy under Linux **before** touching the install button.

The framework is deliberately boring: one POSIX shell library, one file per
test, a manifest, and a GTK front end through `zenity`.  Any module can be run
on its own.  Nothing here is tied to one laptop model; whenever hardware or a
tool is missing the module says so and moves on.

> Neucom Info would approve: this is information technology in the service of
> the person holding the machine, and the report is the deliverable you carry
> away from the Electrosphere.

## The checklist

This is the list of what a normal person does with a device, worked down from
laptops, desktops and phones.  **S** = there is a script for it.  **D** = it is
detected and reported, but there is no separate interactive flow yet.

| # | Thing a person uses | Coverage |
|---|---------------------|----------|
| 1 | CPU works and stays correct under load | **S** `core-cpu` |
| 2 | Memory capacity and correctness | **S** `core-mem` |
| 3 | Swap | **S** `core-mem` |
| 4 | Date, timezone and clock sync | **S** `core-time` |
| 5 | Internal disk / SSD health | **S** `storage-disk` |
| 6 | Free space on disks | **S** `storage-rw` |
| 7 | Reading and writing files without corruption | **S** `storage-rw` |
| 8 | USB flash drives | **S** `usb-storage` |
| 9 | SD card reader | **S** `sdcard` |
| 10 | Screen output, resolution, connectors | **S** `display-output` |
| 11 | External monitor / HDMI / DisplayPort | **S** `display-output` |
| 12 | GPU driver and 3D acceleration | **S** `display-gpu` |
| 13 | Brightness / backlight control | **S** `display-backlight` |
| 14 | Keyboard (all letters and digits) | **S** `input-keyboard` |
| 15 | Function keys and media keys | **D** |
| 16 | Touchpad and mouse (move, click, scroll) | **S** `input-pointer` |
| 17 | Touchscreen (tap, swipe, drag) | **S** `input-touch` |
| 18 | Stylus / drawing tablet | **D** |
| 19 | Game controller | **S** `gamepad` |
| 20 | Speakers and headphone jack | **S** `audio-output` |
| 21 | Microphone | **S** `audio-input` |
| 22 | Webcam | **S** `video-camera` |
| 23 | Wi-Fi scan, join and real connectivity | **S** `network-wifi` |
| 24 | Ethernet (cable, link, DHCP) | **S** `network-ethernet` |
| 25 | DNS and reachability of the Electrosphere | **S** `network-internet` |
| 26 | Bluetooth adapter and discovery | **S** `network-bluetooth` |
| 27 | Bluetooth headset / speaker | **S** `network-btaudio` |
| 28 | USB tethering (RNDIS / CDC) from a phone | **S** `network-rndis` |
| 29 | Mobile broadband / SIM / registration | **S** `network-wwan` |
| 30 | Wi-Fi hotspot / access-point mode | **D** |
| 31 | VPN | **D** (proxy is reported by `network-internet`) |
| 32 | GPS / GNSS | **S** `sensor-gps` |
| 33 | Battery charge and health | **S** `power-battery` |
| 34 | Charger / AC / USB-C power delivery | **S** `power-ac` |
| 35 | Suspend and resume | **S** `power-suspend` |
| 36 | Hibernation | **D** (support is reported by `power-suspend`) |
| 37 | Temperatures, fans and throttling | **S** `thermal` |
| 38 | Motion sensors (accelerometer, gyroscope) | **S** `sensor-motion` |
| 39 | Ambient light and proximity | **S** `sensor-light` |
| 40 | Fingerprint reader | **S** `fingerprint` |
| 41 | Printer and scanner | **S** `printer` (scanner is **D**) |
| 42 | NFC | **D** |
| 43 | Vibration | **D** |
| 44 | Flashlight / camera flash | **D** |
| 45 | Physical buttons (power, volume) | **D** |

The `D` rows are intentional: the ecosystem for those is either phone-only or
needs a vendor daemon that a generic image should not assume.  They are listed
so the suite does not pretend they do not exist, and so a later module can
slot in without redesigning anything.

## Layout

```
livediag                 entry point: menu, selection, running, reporting
lib/common.sh            GUI wrappers, result recording, network/audio helpers
lib/report.sh            results.tsv -> report.txt
tests/tests.list         the manifest: id, category, name, script, timeout, essential, description
tests/NN-*.sh            one module per device function
tests/template.sh        starting point for a new module
Makefile                 check (sh -n everything) and install
packaging/alpine/        APKBUILD for an Alpine package
```

A module is a plain shell script.  It sources `lib/common.sh`, calls
`lg_begin`, detects, optionally asks the person one clear question, and ends
with exactly one of `lg_pass`, `lg_fail`, `lg_warn` or `lg_skip`.  The runner
does not care how a module works; it only reads the manifest and the result
line the module appends to the session's `results.tsv`.

Session output lives in `~/livediag-results/<timestamp>/` by default (override
with `LIVEDIAG_OUTDIR`):

```
results.tsv      timestamp, id, status, name, message, category
run.log          everything the modules printed
environment.txt  kernel, distribution and session details
report.txt       the human-readable summary
```

## Running it

```
livediag                      # menu: full, quick, or pick modules
livediag --quick              # only the essential modules
livediag --all                # everything
livediag --only network-wifi,audio-output
livediag --category Network
livediag --list
livediag --no-ui              # no windows; text prompts in the terminal
livediag --non-interactive    # for automation: skip every manual step
livediag --report ~/livediag-results/20260915-120000
```

A single module also runs by itself, which is what you do while developing
one:

```
LIVEDIAG_SESSION=/tmp/lg sh tests/60-network-wifi.sh
```

## How the interaction works

`zenity` is the only GUI dependency.  `lib/common.sh` wraps every dialog so
modules never call it directly:

| Helper | Purpose |
|--------|---------|
| `lg_ui_info` / `lg_ui_warn` / `lg_ui_error` | report something |
| `lg_ui_yesno` | one yes/no question, returns 0 for yes |
| `lg_ui_input` / `lg_ui_password` | one text or secret line |
| `lg_ui_menu` | single choice from a list |
| `lg_ui_checklist` | multi choice (used by the runner) |
| `lg_ui_text` | scrollable file viewer (report, logs) |
| `lg_busy TITLE CMD OUTFILE` | a pulsating progress window around a command |

When there is no display, or with `--no-ui`, the same helpers degrade to the
terminal.  With `--non-interactive` they answer "no" to manual questions, so
the suite can run unattended and still produce a report.

Every module is written so that the safe path is the default.  The read/write
test writes one file under `$HOME` (or `LIVEDIAG_RW_TARGET`) and deletes it;
the printer test asks before spending paper; nothing formats or repartitions.

## Adding a module

1. `cp tests/template.sh tests/56-my-thing.sh`
2. add a line to `tests/tests.list`
3. write the detection and the single final result
4. `dash -n tests/56-my-thing.sh`
5. run it headless: `LIVEDIAG_NONINTERACTIVE=1 sh tests/56-my-thing.sh`

Keep detection generic.  Prefer `/sys`, `/proc` and standard tools; if a
specific tool would help but may be absent, guard it with `lg_have` and fall
back.  Do not hard-code a vendor, a device path or a model.

## Verification

Every module in this tree was checked for:

* **Syntax** under `dash` (strict POSIX parsing).
* **A result on every path**: run headless with `LIVEDIAG_NONINTERACTIVE=1`,
  each one appends exactly one line to `results.tsv`, and none hangs.
* **Graceful absence**: modules for hardware this machine does not have report
  `SKIP`, not an error.
* **No hardware assumptions**: detection goes through `/sys`/`/proc`, `lspci`,
  `lsusb`, `iw` or the standard sound/network stacks; there is no vendor list.
* **A human flow where one is needed**: Wi-Fi connects to a hotspot and probes
  five independent resolvers; keyboard has the person type a sentence;
  battery and charger have the person unplug and replug; storage writes,
  flushes and reads back.

The five resolvers are `1.1.1.1`, `8.8.8.8`, `9.9.9.9`, `208.67.222.222` and
`8.8.4.4`.  Each probe tries ICMP first and HTTPS on port 443 second, because
some captive networks block ping but still work.

## Packaging

See `packaging/alpine/README.md`.  The image needs a graphical session (X11
or Wayland), `zenity`, and the runtime tools listed in the APKBUILD.  Nothing
in the suite requires a specific desktop.
