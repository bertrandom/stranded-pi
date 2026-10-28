# rpi-jc-ansible

Install Johnny Castaway on a Raspberry Pi using Ansible

It builds [jc_reborn](https://github.com/jno6809/jc_reborn), an open source engine for the 1992 Johnny Castaway screen saver, and runs it full screen on the Pi's HDMI output during the day. At night it stops Johnny and turns the display off.

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
| jc_reborn source and binary, pinned to a known commit | `/opt/jc_reborn` |
| Original game data (`RESOURCE.MAP`, `RESOURCE.001`, sounds), checksum-verified | `/var/cache/johnny.zip`, extracted into `/opt/jc_reborn` |
| `johnny` system user (groups `video`, `render`, `input`, `audio`) | home is `/var/lib/johnny` |
| Service that runs Johnny | `/etc/systemd/system/jc_reborn.service` |
| Day/night schedule | `/usr/local/sbin/jc-schedule`, `jc-schedule.service`, `jc-schedule.timer` |

### Running Johnny

`jc_reborn.service` runs `jc_reborn hotkeys` as the unprivileged `johnny` user, drawing straight to the screen through SDL's KMS/DRM driver (no desktop or X needed). It takes over `/dev/tty1`, so the login prompt on tty1 is masked; the other consoles (Ctrl+Alt+F2 and up) and SSH still work normally.

If Johnny exits, whether it crashes or someone presses Esc on an attached keyboard, systemd restarts it after 5 seconds. Its output goes to the journal:

```
journalctl -u jc_reborn
```

Johnny keeps its story progress (which day of the story it's on, plus the date for holiday scenes) in `/var/lib/johnny/.jc_reborn`.

With a keyboard attached, the hotkeys are: Esc to quit (and restart), Space to pause, Return to step a frame while paused, M to toggle max speed.

### Day/night schedule

`jc-schedule` checks the current local time:

- **Between `jc_on_time` and `jc_off_time`** (08:00 to 22:00 by default): wakes the display and starts `jc_reborn.service`.
- **Otherwise**: stops `jc_reborn.service`, blanks the console (which turns off the HDMI signal so the monitor sleeps), and, if the display is a TV that supports HDMI-CEC, puts it into standby.

It runs at boot (`jc-schedule.service`) and at both switch times (`jc-schedule.timer`). Because it always sets the state from the current time, a reboot in the middle of the night stays dark.

To change the hours, edit `jc_on_time` and `jc_off_time` in `main.yml` and run the playbook again.

To override by hand, `sudo systemctl start jc_reborn` or `sudo systemctl stop jc_reborn`. The override lasts until the next switch time. To see when the next switch happens:

```
systemctl list-timers jc-schedule.timer
```

### Boot speed

Nothing here needs the network, so the playbook disables `NetworkManager-wait-online.service`, and disables cloud-init (`/etc/cloud/cloud-init.disabled`), which is only needed on the first boot of an image made with Raspberry Pi Imager.

## Notes

Tested on a Raspberry Pi 3 Model B Rev 1.2 running Raspberry Pi OS Lite 64-bit Trixie
