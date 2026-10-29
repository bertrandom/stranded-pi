#!/bin/bash
# Builds a Raspberry Pi OS Lite image with Johnny Castaway preinstalled, by
# running main.yml inside the official image. Raspberry Pi Imager can then
# flash it and apply its usual settings (user, Wi-Fi, SSH) on first boot.
#
# Runs as root on arm64 Linux. From a Mac (or anywhere with Docker), use
# image/build-docker.sh instead.
#
# Writes to image/out:
#   <name>.img.xz          the image
#   <name>.img.xz.sha256   its checksum
#   repo.json              a Raspberry Pi Imager repository listing the image
set -euo pipefail

# Official Raspberry Pi OS Lite (64-bit) image to build on
BASE_URL=${BASE_URL:-https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-10-06/2026-10-06-raspios-trixie-arm64-lite.img.xz}
# Room added to the root filesystem for jc_reborn and its build dependencies
EXTRA_SPACE=${EXTRA_SPACE:-1536M}
# Where the image will be downloaded from, for repo.json. Defaults to the
# local file, for testing
IMAGE_URL_BASE=${IMAGE_URL_BASE:-}
# image/out as seen from outside Docker, for the default file:// URL
HOST_OUT_DIR=${HOST_OUT_DIR:-}

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK=$REPO_DIR/image/work
OUT=$REPO_DIR/image/out
MNT=$WORK/mnt
DATE=$(date +%Y-%m-%d)
NAME=$DATE-johnny-castaway-raspios-trixie-arm64-lite
IMG=$WORK/$NAME.img

ROOT_DEV=
BOOT_DEV=

log() { echo; echo "== $*"; }

cleanup() {
    set +e
    for dir in run sys proc dev/pts dev boot/firmware ""; do
        mountpoint -q "$MNT/$dir" && umount "$MNT/$dir"
    done
    [ -n "$BOOT_DEV" ] && losetup -d "$BOOT_DEV"
    [ -n "$ROOT_DEV" ] && losetup -d "$ROOT_DEV"
}
trap cleanup EXIT

if [ "$(id -u)" != 0 ] || [ "$(uname -m)" != aarch64 ]; then
    echo "Run as root on arm64 Linux, or use image/build-docker.sh" >&2
    exit 1
fi

log "Installing build tools"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    ansible ca-certificates curl e2fsprogs fdisk python3 xz-utils zerofree >/dev/null

mkdir -p "$WORK" "$OUT" "$MNT"

log "Downloading $(basename "$BASE_URL")"
BASE_XZ=$WORK/$(basename "$BASE_URL")
if [ ! -f "$BASE_XZ" ]; then
    curl -fL --progress-bar -o "$BASE_XZ.part" "$BASE_URL"
    mv "$BASE_XZ.part" "$BASE_XZ"
fi
expected=$(curl -fsSL "$BASE_URL.sha256" | cut -d' ' -f1)
echo "$expected  $BASE_XZ" | sha256sum -c -

log "Extracting and growing the image by $EXTRA_SPACE"
xz -dc "$BASE_XZ" > "$IMG"
truncate -s "+$EXTRA_SPACE" "$IMG"
echo ", +" | sfdisk -q -N 2 --no-reread --no-tell-kernel "$IMG"

# Loop devices by offset: partition devices (loopNpX) don't appear in Docker
part() {   # part <number> <start|size>, in bytes
    sfdisk -J "$IMG" | python3 -c "
import json, sys
p = json.load(sys.stdin)['partitiontable']['partitions'][$1 - 1]
print(p['$2'] * 512)"
}
BOOT_DEV=$(losetup -f --show -o "$(part 1 start)" --sizelimit "$(part 1 size)" "$IMG")
ROOT_DEV=$(losetup -f --show -o "$(part 2 start)" --sizelimit "$(part 2 size)" "$IMG")
e2fsck -fy "$ROOT_DEV" >/dev/null || [ $? -le 1 ]
resize2fs "$ROOT_DEV"

log "Mounting the image"
mount "$ROOT_DEV" "$MNT"
mount "$BOOT_DEV" "$MNT/boot/firmware"
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sysfs "$MNT/sys"
mount -t tmpfs tmpfs "$MNT/run"

# Network access for apt and git, and no services started by package installs
mv "$MNT/etc/resolv.conf" "$WORK/resolv.conf.orig"
cp /etc/resolv.conf "$MNT/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$MNT/usr/sbin/policy-rc.d"
chmod +x "$MNT/usr/sbin/policy-rc.d"
ls "$MNT"/etc/ssh/ssh_host_* > "$WORK/ssh-keys-before" 2>/dev/null || true

log "Running the playbook in the image"
cat > "$WORK/inventory.ini" <<EOF
[pis]
image ansible_connection=community.general.chroot ansible_host=$MNT ansible_python_interpreter=/usr/bin/python3
EOF
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$WORK/inventory.ini" \
    -e jc_image_build=true "$REPO_DIR/main.yml"

log "Cleaning up the image"
chroot "$MNT" apt-get clean
rm -rf "$MNT"/var/lib/apt/lists/* "$MNT/root/.ansible" "$MNT"/tmp/* "$MNT"/var/tmp/*
rm -f "$MNT/usr/sbin/policy-rc.d"
rm -f "$MNT/etc/resolv.conf"
mv "$WORK/resolv.conf.orig" "$MNT/etc/resolv.conf"
# Host keys must be generated on each Pi's first boot, never shared
for key in "$MNT"/etc/ssh/ssh_host_*; do
    [ -e "$key" ] && ! grep -qx "$key" "$WORK/ssh-keys-before" && rm -f "$key"
done
find "$MNT/var/log" -type f -exec truncate -s 0 {} +

log "Unmounting"
cleanup
ROOT_DEV=$(losetup -f --show -o "$(part 2 start)" --sizelimit "$(part 2 size)" "$IMG")
e2fsck -fy "$ROOT_DEV" >/dev/null || [ $? -le 1 ]
zerofree "$ROOT_DEV"     # zero unused blocks so the image compresses well
losetup -d "$ROOT_DEV"
ROOT_DEV=
BOOT_DEV=

log "Compressing"
extract_size=$(stat -c %s "$IMG")
extract_sha256=$(sha256sum "$IMG" | cut -d' ' -f1)
xz -T0 -6 -f "$IMG"
mv "$IMG.xz" "$OUT/$NAME.img.xz"
download_size=$(stat -c %s "$OUT/$NAME.img.xz")
download_sha256=$(sha256sum "$OUT/$NAME.img.xz" | cut -d' ' -f1)
echo "$download_sha256  $NAME.img.xz" > "$OUT/$NAME.img.xz.sha256"

log "Writing repo.json"
if [ -n "$IMAGE_URL_BASE" ]; then
    url=${IMAGE_URL_BASE%/}/$NAME.img.xz
else
    url=file://${HOST_OUT_DIR:-$OUT}/$NAME.img.xz
fi
curl -fsSL https://downloads.raspberrypi.com/os_list_imagingutility_v4.json \
  | URL=$url DATE=$DATE EXTRACT_SIZE=$extract_size EXTRACT_SHA256=$extract_sha256 \
    DOWNLOAD_SIZE=$download_size DOWNLOAD_SHA256=$download_sha256 \
    python3 -c '
import json, os, sys
official = json.load(sys.stdin)
e = os.environ
os_list = {
    # The device list, so that Imager can ask which Raspberry Pi it is for
    "imager": official["imager"],
    "os_list": [{
        "name": "Johnny Castaway",
        "description": "Raspberry Pi OS Lite (64-bit) running the Johnny Castaway screensaver",
        "icon": "https://downloads.raspberrypi.com/raspios_armhf/Raspberry_Pi_OS_(32-bit).png",
        "url": e["URL"],
        "release_date": e["DATE"],
        "extract_size": int(e["EXTRACT_SIZE"]),
        "extract_sha256": e["EXTRACT_SHA256"],
        "image_download_size": int(e["DOWNLOAD_SIZE"]),
        "image_download_sha256": e["DOWNLOAD_SHA256"],
        # Same as Raspberry Pi OS Trixie: settings are applied by cloud-init
        "init_format": "cloudinit-rpi",
        "devices": ["pi5-64bit", "pi4-64bit", "pi3-64bit"],
        "capabilities": [],
    }],
}
json.dump(os_list, sys.stdout, indent=2)
' > "$OUT/repo.json"

log "Done"
ls -lh "$OUT"
