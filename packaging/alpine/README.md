# Packaging livediag for Alpine

`APKBUILD` packages the suite as `livediag`.  The entry point lands in
`/usr/bin/livediag` and the library plus modules in `/usr/share/livediag/`,
which is one of the locations the runner looks in.

## Build

The `source=` line in `APKBUILD` is a placeholder for the repository tarball.
Replace `OWNER` with the account that hosts this project, or point it at a
local tarball while testing:

```sh
cd packaging/alpine
abuild-keygen -a -i          # once
abuild -r                    # builds and installs into ~/packages
```

`abuild` runs the `check()` function, which parses every shell file with the
BusyBox `sh -n`.

## Live image

The package only pulls in the tools that every run needs.  An install-party
image wants the optional tools too, otherwise several modules will report
`SKIP`.  A reasonable `world` file:

```
alpine-base
openrc
eudev
linux-lts
networkmanager
networkmanager-openrc
wpa_supplicant
iwd
bluez
bluez-openrc
modemmanager
modemmanager-openrc
pipewire
pipewire-pulse
wireplumber
alsa-utils
alsa-utils-openrc
mesa-dri-gallium
mesa-demos
vulkan-tools
libinput-tools
v4l-utils
ffmpeg
fswebcam
usbutils
pciutils
util-linux
lm-sensors
smartmontools
upower
memtester
iio-sensor-proxy
fprintd
linuxconsoletools
cups-client
gpsd
zenity
font-dejavu
livediag
```

On top of that the image needs a display server and a compositor or window
manager so that `zenity` has somewhere to draw.  The suite reads
`DISPLAY`/`WAYLAND_DISPLAY`; if neither is set it falls back to the terminal,
and `livediag --non-interactive` runs fully headless.

## Cross-checking the package

After `abuild -r`:

```sh
apk add --allow-untrusted ~/packages/*/livediag-*.apk
livediag --list
livediag --quick --non-interactive
```
