#!/bin/bash
# Runs image/build.sh in an arm64 Debian container. Needs Docker; on an
# Apple Silicon Mac it runs natively, elsewhere through emulation (slow).
# --privileged is needed to attach the image as loop devices.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)

exec docker run --rm --privileged --platform linux/arm64 \
    -v "$REPO_DIR:/work" \
    -e BASE_URL -e EXTRA_SPACE -e IMAGE_URL_BASE \
    -e HOST_OUT_DIR="$REPO_DIR/image/out" \
    debian:trixie /work/image/build.sh
