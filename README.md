# stranded-pi

Turn a Raspberry Pi into a Johnny Castaway screen: the 1992 screen saver, playing full screen on the Pi's HDMI output, with a web page to control it and a night mode that turns the display off at night.

It runs [stranded](https://github.com/bertrandom/stranded), an open source engine for the screen saver (a fork of [Johnny Reborn](https://github.com/jno6809/jc_reborn)), installed as a Debian package. This repository builds a ready-to-flash SD card image with it, and has a script to set it up on a Pi that's already running Raspberry Pi OS.

Works on the Raspberry Pi Zero 2 W, 3, 4 and 5, with Raspberry Pi OS Lite (64-bit) Trixie.

## SD card image

The image is the official Raspberry Pi OS Lite (64-bit) with stranded preinstalled. [Raspberry Pi Imager](https://www.raspberrypi.com/software/) still lets you set the hostname, username and password, Wi-Fi, SSH and so on while flashing, as for Raspberry Pi OS.

### Building it

On a Mac with Apple Silicon (or any machine with Docker):

```
./image/build-docker.sh
```

On arm64 Linux, `sudo ./image/build.sh` does the same without Docker. It takes the official image, grows it a little, runs `setup.sh` inside it, and writes to `image/out`:

- `stranded-<version>-raspios-trixie-arm64-lite.img.xz`, the image, with its `.sha256`
- `repo.json`, a Raspberry Pi Imager repository listing the image

It installs the latest [stranded release](https://github.com/bertrandom/stranded/releases). To pick another one, set `STRANDED_VERSION`, eg. `STRANDED_VERSION=2026.10.29 ./image/build-docker.sh`, or `STRANDED_DEB` to a `.deb` file in this directory.

By default `repo.json` points at the image on your disk. To publish the image somewhere, set `IMAGE_URL_BASE` to the URL of the folder you'll upload it to, eg. `IMAGE_URL_BASE=https://example.com/stranded ./image/build-docker.sh`, and upload both files there. Keep in mind that the image includes the original game's data files.

### Flashing it

Imager only offers its settings step for images listed in a repository, not for an image picked with "Use custom". So point Imager at `repo.json`:

1. In Raspberry Pi Imager, open **App Options**, set **Content Repository** to **Use custom file** and choose `repo.json` (or a URL to it). On a Mac you can also start it with `open -a "Raspberry Pi Imager" --args --repo /path/to/repo.json`.
2. Choose your Raspberry Pi model, then **Stranded** as the operating system, and your SD card.
3. Fill in the customisation settings: hostname, username and password, Wi-Fi, SSH. Then write the card.

On first boot the Pi applies those settings, expands the filesystem to fill the card, and starts Johnny. The web page is at `http://<hostname>/`.

The image keeps cloud-init enabled, since it's what applies Imager's settings, so it boots a few seconds slower. Running `setup.sh` on the Pi afterwards disables it.

## Setting up a running Pi

On a Pi running Raspberry Pi OS Lite (64-bit) Trixie, copy `setup.sh` to it and run it as root, eg. from this directory:

```
scp setup.sh <your Pi>:
ssh <your Pi> sudo ./setup.sh
```

It installs the latest stranded release, downloads the game's data files, writes the default settings, and starts Johnny. Run it again to update to the latest release; it keeps the settings. `STRANDED_VERSION` and `STRANDED_DEB` work as for the image.

## How it works

### What gets installed

The [stranded package](https://github.com/bertrandom/stranded#debian-package) installs the program, a `stranded` system user, and a `stranded.service` that runs it on the Pi's screen. `setup.sh` adds:

| What | Where |
| --- | --- |
| The original game's data files (`RESOURCE.MAP`, `RESOURCE.001`, sounds), checksum-verified, from `RESOURCES_URL` | `/var/lib/stranded` |
| Default settings: night mode off, set to 22:00 to 08:00 with HDMI-CEC for when it's turned on | `/var/lib/stranded/.stranded` |
| No waiting for the network at boot | `NetworkManager-wait-online.service` disabled |
| On a running Pi, cloud-init disabled | `/etc/cloud/cloud-init.disabled` |

Settings are only written when they aren't set yet, so running `setup.sh` again never undoes changes made on the web page.

### Running Johnny

`stranded.service` runs `stranded hotkeys web` as the unprivileged `stranded` user, drawing straight to the screen through SDL's KMS/DRM driver (no desktop or X needed). It takes over `/dev/tty1`, so the login prompt there is turned off while the service is enabled; the other consoles (Ctrl+Alt+F2 and up) and SSH still work normally.

If Johnny exits, whether it crashes or someone presses Esc on an attached keyboard, systemd restarts it after 5 seconds. Its output goes to the journal:

```
journalctl -u stranded
```

With a keyboard attached, the hotkeys are: Esc to quit (and restart), Space to pause, Return to step a frame while paused, N for the next scene, M to toggle max speed.

### Web page

Open `http://<your Pi>/` to see a live preview of the screen and which scene is playing, pause Johnny, step through frames, skip to the next scene, toggle max speed, change the day of the story, turn sound and hotkeys on or off, set up night mode, and restart Johnny or reboot or shut down the Pi. Changes are saved right away.

Everything on the page is also available as an API, for example:

```
curl http://<your Pi>/api/status
curl -X POST http://<your Pi>/api/toggle-pause
curl -H 'Content-Type: application/json' -d '{"nightStart": "22:00", "nightEnd": "08:00"}' http://<your Pi>/api/settings
```

`curl http://<your Pi>/api` lists every endpoint and setting, and [stranded's README](https://github.com/bertrandom/stranded#web-control-and-night-mode) describes them.

There's no password: anyone on your network can change settings, restart Johnny, or reboot and shut down the Pi. After a shutdown, the Pi stays off until it's unplugged and plugged back in.

### Night mode

During the night hours Johnny pauses, the screen goes black and the Pi turns its HDMI output off, so the monitor sleeps. If the display is a TV that supports HDMI-CEC, it's put in standby too. In the morning the display comes back on and Johnny carries on where he left off.

Night mode is off by default. Turn it on, and change its hours (22:00 to 08:00 by default), on the web page. The page also has buttons to turn the display off or on right away; that lasts until the next scheduled switch.

### Widescreen displays

On a 16:9 (or any wider than 4:3) display, the picture isn't stretched: the ocean and sky are extended to the sides of the screen.
