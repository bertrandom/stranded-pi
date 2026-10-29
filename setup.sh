#!/bin/bash
# Sets up a Raspberry Pi to play Johnny Castaway full screen: installs the
# stranded package, the original game's data files and default settings.
# Run as root on the Pi, or by image/build.sh inside an SD card image.
#
# Environment:
#   STRANDED_DEB       a stranded .deb to install, instead of downloading one
#   STRANDED_VERSION   the release to download, eg. 2026.10.29 (default: latest)
#   IMAGE_BUILD=1      set up an SD card image rather than a running Pi
set -euo pipefail

# The original game's data files, which can't be distributed with stranded
RESOURCES_URL=${RESOURCES_URL:-https://test.bert.org/johnny.zip}
RESOURCES_SHA256=4db347c0f57a4d92bad23234cc91034eeef5073d92a79e5ec1e0461f47393980

# Initial settings, only written when not set yet: after that, change them
# on the web page
DEFAULT_SETTINGS="nightMode=1 nightStart=22:00 nightEnd=08:00 cec=1"

STRANDED_DEB=${STRANDED_DEB:-}
STRANDED_VERSION=${STRANDED_VERSION:-}
IMAGE_BUILD=${IMAGE_BUILD:-}
RELEASES=https://api.github.com/repos/bertrandom/stranded/releases
HOME_DIR=/var/lib/stranded

log() { echo "== $*"; }

if [ "$(id -u)" != 0 ]; then
    echo "Run as root, eg. sudo $0" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl unzip >/dev/null

if [ -z "$STRANDED_DEB" ]; then
    if [ -n "$STRANDED_VERSION" ]; then
        release=$RELEASES/tags/v$STRANDED_VERSION
    else
        release=$RELEASES/latest
    fi
    url=$(curl -fsSL "$release" | python3 -c '
import json, sys
for asset in json.load(sys.stdin)["assets"]:
    if asset["name"].endswith("_arm64.deb"):
        print(asset["browser_download_url"])
        break')
    if [ -z "$url" ]; then
        echo "No arm64 package in $release" >&2
        exit 1
    fi
    log "Downloading $(basename "$url")"
    STRANDED_DEB=$TMP/$(basename "$url")
    curl -fsSL -o "$STRANDED_DEB" "$url"
fi

log "Installing $(basename "$STRANDED_DEB")"
apt-get install -y -qq "$(realpath "$STRANDED_DEB")" >/dev/null

if [ ! -f "$HOME_DIR/RESOURCE.MAP" ]; then
    log "Downloading the game's data files"
    curl -fsSL -o "$TMP/resources.zip" "$RESOURCES_URL"
    echo "$RESOURCES_SHA256  $TMP/resources.zip" | sha256sum -c --quiet -
    unzip -q -o "$TMP/resources.zip" -d "$HOME_DIR"
    chown -R stranded:stranded "$HOME_DIR"
fi

log "Setting default settings"
settings=$HOME_DIR/.stranded
touch "$settings"
for setting in $DEFAULT_SETTINGS; do
    grep -q "^${setting%%=*}=" "$settings" || echo "$setting" >> "$settings"
done
chown stranded:stranded "$settings"

# Nothing here needs to wait for the network: boot faster
log "Not waiting for the network at boot"
systemctl disable --quiet NetworkManager-wait-online.service 2>/dev/null || true

if [ -z "$IMAGE_BUILD" ]; then
    # cloud-init only matters for the first boot of an SD card image, where
    # it applies Raspberry Pi Imager's settings
    log "Disabling cloud-init"
    touch /etc/cloud/cloud-init.disabled

    # The package keeps the login prompt off tty1 from the next boot: until
    # then, stop the one running there, as stranded needs tty1
    log "Starting stranded"
    systemctl stop getty@tty1.service
    systemctl restart stranded
fi

log "Done"
