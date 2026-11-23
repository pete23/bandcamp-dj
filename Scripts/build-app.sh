#!/bin/sh
# Builds "Bandcamp Sync.app" from the BandcampSyncApp target into .build/, signed ad hoc.
# Usage: Scripts/build-app.sh [destination folder]   (e.g. /Applications)
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product BandcampSyncApp
bin="$(swift build -c release --show-bin-path)"

app="${1:-.build}/Bandcamp Sync.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/BandcampSyncApp" "$app/Contents/MacOS/"
cp App/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "$app"
