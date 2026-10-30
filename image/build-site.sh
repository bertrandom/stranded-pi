#!/bin/bash
# Builds the image for stranded.bert.org: runs image/build-docker.sh with the
# image's URL on the site, then copies repo.json into the site's public/ and
# the image into public/images/, for the site's next build.
#
# SITE_DIR is the stranded.bert.org checkout, by default next to this one.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SITE_DIR=${SITE_DIR:-$REPO_DIR/../stranded.bert.org}
OUT=$REPO_DIR/image/out

if [ ! -d "$SITE_DIR/public" ]; then
    echo "No public/ in $SITE_DIR. Set SITE_DIR to the stranded.bert.org checkout" >&2
    exit 1
fi

IMAGE_URL_BASE=https://stranded.bert.org/images "$REPO_DIR/image/build-docker.sh"

# The image that repo.json lists, as image/out may have older ones
name=$(sed -n 's|.*"url": "https://stranded.bert.org/images/\([^"]*\)".*|\1|p' "$OUT/repo.json")
if [ -z "$name" ] || [ ! -f "$OUT/$name" ]; then
    echo "Couldn't find the image repo.json lists in $OUT" >&2
    exit 1
fi

mkdir -p "$SITE_DIR/public/images"
cp "$OUT/$name" "$OUT/$name.sha256" "$SITE_DIR/public/images/"
cp "$OUT/repo.json" "$SITE_DIR/public/repo.json"

echo
echo "== Copied to $SITE_DIR/public"
ls -lh "$SITE_DIR/public/repo.json" "$SITE_DIR/public/images"
