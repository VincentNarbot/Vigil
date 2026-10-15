#!/bin/zsh
# Builds Vigil.app and installs it into ~/Applications.
set -euo pipefail
cd "${0:A:h}"

APP=build/Vigil.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

xcrun swiftc -O -target arm64-apple-macos13 Sources/main.swift -o "$APP/Contents/MacOS/Vigil"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

pkill -x Vigil 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/Vigil.app
cp -R "$APP" ~/Applications/Vigil.app
open ~/Applications/Vigil.app
echo "Installed ~/Applications/Vigil.app"
