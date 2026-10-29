# rpi-jc-ansible

Install Johnny Castaway on a Raspberry Pi using Ansible

It builds [a fork of jc_reborn](https://github.com/bertrandom/jc_reborn), an open source engine for the 1992 Johnny Castaway screen saver, and runs it full screen on the Pi's HDMI output. The fork adds a web page for changing settings and controlling Johnny, and a night mode that turns the display off at night.

## Installation

On Raspberry Pi:
```
sudo apt install ansible git
git clone https://github.com/bertrandom/rpi-jc-ansible.git
cd rpi-jc-ansible
```

Then run:
```
ansible-playbook -i inventory.yml main.yml -l local --ask-become-pass
```

To run it from another machine over SSH instead, use `-l pijohnny` (or add your own host to `inventory.yml`).

## SD card image

Instead of running the playbook on a Pi, you can build an SD card image with everything already installed, and flash it with [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Imager still lets you set the username, password, Wi-Fi, SSH and so on while flashing, as it does for Raspberry Pi OS.

### Building it

On a Mac with Apple Silicon (or any machine with Docker):

```
./image/build-docker.sh
```

On arm64 Linux, `sudo ./image/build.sh` does the same without Docker. It takes the official Raspberry Pi OS Lite (64-bit) Trixie image, grows it, runs `main.yml` inside it (with `jc_image_build=true`), and writes to `image/out`:

- `<date>-johnny-castaway-raspios-trixie-arm64-lite.img.xz`, the image, with its `.sha256`
- `repo.json`, a Raspberry Pi Imager repository listing the image

By default `repo.json` points at the image on your disk. To publish the image somewhere, set `IMAGE_URL_BASE` to the URL of the folder you'll upload it to, eg. `IMAGE_URL_BASE=https://example.com/johnny ./image/build-docker.sh`, and upload both files there.

### Flashing it

Imager only offers its settings step for images listed in a repository, not for an image picked with "Use custom". So point Imager at `repo.json`:

1. In Raspberry Pi Imager, open **App Options**, set **Content Repository** to **Use custom file** and choose `repo.json` (or a URL to it). On a Mac you can also start it with `open -a "Raspberry Pi Imager" --args --repo /path/to/repo.json`.
2. Choose your Raspberry Pi model (Zero 2 W, 3, 4 or 5), then **Johnny Castaway** as the operating system, and your SD card.
3. Fill in the customisation settings: hostname, username and password, Wi-Fi, SSH. Then write the card.

On first boot the Pi applies those settings, expands the filesystem to fill the card, and starts Johnny. The web page is at `http://<hostname>/`.

Unlike a Pi set up with the playbook, an image keeps cloud-init enabled, since it's what applies Imager's settings, so it boots a few seconds slower. Running the playbook on the Pi afterwards disables it.

## How it works

### What the playbook installs

| What | Where |
| --- | --- |
| jc_reborn source and binary, built from the fork at a pinned commit | `/opt/jc_reborn` |
| Original game data (`RESOURCE.MAP`, `RESOURCE.001`, sounds), checksum-verified | `/var/cache/johnny.zip`, extracted into `/opt/jc_reborn` |
| `johnny` system user (groups `video`, `render`, `input`, `audio`) | home is `/var/lib/johnny` |
| Service that runs Johnny | `/etc/systemd/system/jc_reborn.service` |
| polkit rule that lets `johnny` reboot and shut down the Pi, for the web page | `/etc/polkit-1/rules.d/50-jc_reborn.rules` |
| jc_reborn settings and story progress | `/var/lib/johnny/.jc_reborn` |

### Running Johnny

`jc_reborn.service` runs `jc_reborn hotkeys web` as the unprivileged `johnny` user, drawing straight to the screen through SDL's KMS/DRM driver (no desktop or X needed). It takes over `/dev/tty1`, so `getty@tty1.service` (the login prompt on tty1) has an override that skips it while Johnny is installed; the other consoles (Ctrl+Alt+F2 and up) and SSH still work normally.

If Johnny exits, whether it crashes or someone presses Esc on an attached keyboard, systemd restarts it after 5 seconds. Its output goes to the journal:

```
journalctl -u jc_reborn
```

Johnny keeps its settings and story progress (which day of the story it's on, plus the date for holiday scenes) in `/var/lib/johnny/.jc_reborn`.

With a keyboard attached, the hotkeys are: Esc to quit (and restart), Space to pause, Return to step a frame while paused, M to toggle max speed.

### Web page

The `web` option starts a web server on port 80: open `http://<your Pi>/` (for example `http://pijohnny/`) to see a live preview of the screen and which scene is playing, pause Johnny, step through frames, skip to the next scene, toggle max speed, change the day of the story, turn sound and hotkeys on or off, and set up night mode. Changes are saved right away.

Everything on the page is also available as an API, for example:

```
curl http://pijohnny/api/status
curl -X POST http://pijohnny/api/toggle-pause
curl -H 'Content-Type: application/json' -d '{"nightStart": "22:00", "nightEnd": "08:00"}' http://pijohnny/api/settings
```

`curl http://pijohnny/api` lists every endpoint and setting, and the [fork's README](https://github.com/bertrandom/jc_reborn#web-control-and-night-mode) describes them. Normally only root can listen on port 80, so the service grants `johnny` just that one permission (`AmbientCapabilities=CAP_NET_BIND_SERVICE`).

The System section at the bottom of the page restarts Johnny, or reboots or shuts down the Pi. jc_reborn runs `systemctl reboot` or `systemctl poweroff`, which a polkit rule installed by the playbook allows `johnny` to do, and nothing else. After a shutdown, the Pi stays off until it's unplugged and plugged back in.

There's no password: anyone on your network can change settings, restart Johnny, or reboot and shut down the Pi.

### Night mode

During the night hours Johnny pauses, the screen goes black and the Pi turns its HDMI output off, so the monitor sleeps. If the display is a TV that supports HDMI-CEC, it's put in standby too. In the morning the display comes back on and Johnny carries on where he left off.

Night mode is on by default, from 22:00 to 08:00. Change the hours, or turn it off, on the web page. The page also has buttons to turn the display off or on right away; that lasts until the next scheduled switch.

The defaults are set by `jc_default_settings` in `main.yml`. The playbook only writes a setting that isn't in `/var/lib/johnny/.jc_reborn` yet, so running it again never undoes changes made on the web page.

### Boot speed

Nothing here needs the network, so the playbook disables `NetworkManager-wait-online.service`, and disables cloud-init (`/etc/cloud/cloud-init.disabled`), which is only needed on the first boot of an image made with Raspberry Pi Imager.

## Notes

Tested on a Raspberry Pi 3 Model B Rev 1.2 running Raspberry Pi OS Lite 64-bit Trixie
