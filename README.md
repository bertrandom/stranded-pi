# rpi-jc-ansible

Install Johnny Castaway on a Raspberry Pi using Ansible

It builds [a fork of jc_reborn](https://github.com/bertrandom/jc_reborn/tree/web-control), an open source engine for the 1992 Johnny Castaway screen saver, and runs it full screen on the Pi's HDMI output. The fork adds a web page for changing settings and controlling Johnny, and a night mode that turns the display off at night.

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

## How it works

### What the playbook installs

| What | Where |
| --- | --- |
| jc_reborn source and binary, built from the fork at a pinned commit | `/opt/jc_reborn` |
| Original game data (`RESOURCE.MAP`, `RESOURCE.001`, sounds), checksum-verified | `/var/cache/johnny.zip`, extracted into `/opt/jc_reborn` |
| `johnny` system user (groups `video`, `render`, `input`, `audio`) | home is `/var/lib/johnny` |
| Service that runs Johnny | `/etc/systemd/system/jc_reborn.service` |
| jc_reborn settings and story progress | `/var/lib/johnny/.jc_reborn` |

### Running Johnny

`jc_reborn.service` runs `jc_reborn hotkeys web` as the unprivileged `johnny` user, drawing straight to the screen through SDL's KMS/DRM driver (no desktop or X needed). It takes over `/dev/tty1`, so the login prompt on tty1 is masked; the other consoles (Ctrl+Alt+F2 and up) and SSH still work normally.

If Johnny exits, whether it crashes or someone presses Esc on an attached keyboard, systemd restarts it after 5 seconds. Its output goes to the journal:

```
journalctl -u jc_reborn
```

Johnny keeps its settings and story progress (which day of the story it's on, plus the date for holiday scenes) in `/var/lib/johnny/.jc_reborn`.

With a keyboard attached, the hotkeys are: Esc to quit (and restart), Space to pause, Return to step a frame while paused, M to toggle max speed.

### Web page

The `web` option starts a web server on port 80: open `http://<your Pi>/` (for example `http://pijohnny/`) to see whether Johnny is playing, pause him, step through frames, toggle max speed, change the day of the story, turn sound and hotkeys on or off, and set up night mode. Changes are saved right away.

Everything on the page is also available as an API, for example:

```
curl http://pijohnny/api/status
curl -X POST http://pijohnny/api/toggle-pause
curl -d nightStart=22:00 -d nightEnd=08:00 http://pijohnny/api/settings
```

See the [fork's README](https://github.com/bertrandom/jc_reborn/tree/web-control#web-control-and-night-mode) for the full list. Normally only root can listen on port 80, so the service grants `johnny` just that one permission (`AmbientCapabilities=CAP_NET_BIND_SERVICE`).

There's no password: anyone on your network can change settings or quit Johnny (systemd restarts it).

### Night mode

During the night hours Johnny pauses, the screen goes black and the Pi turns its HDMI output off, so the monitor sleeps. If the display is a TV that supports HDMI-CEC, it's put in standby too. In the morning the display comes back on and Johnny carries on where he left off.

Night mode is on by default, from 22:00 to 08:00. Change the hours, or turn it off, on the web page. The page also has buttons to turn the display off or on right away; that lasts until the next scheduled switch.

The defaults are set by `jc_default_settings` in `main.yml`. The playbook only writes a setting that isn't in `/var/lib/johnny/.jc_reborn` yet, so running it again never undoes changes made on the web page.

### Boot speed

Nothing here needs the network, so the playbook disables `NetworkManager-wait-online.service`, and disables cloud-init (`/etc/cloud/cloud-init.disabled`), which is only needed on the first boot of an image made with Raspberry Pi Imager.

## Notes

Tested on a Raspberry Pi 3 Model B Rev 1.2 running Raspberry Pi OS Lite 64-bit Trixie
