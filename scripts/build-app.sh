#!/bin/bash
# Builds build/Ledge.app. Pass --install to also copy it to /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
APP=build/Ledge.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Ledge"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ledge"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon, drawn by scripts/make-icon.swift and cached in build/.
if [ ! -f build/AppIcon.icns ]; then
    ICONSET=build/AppIcon.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    swift scripts/make-icon.swift build/icon-1024.png
    for size in 16 32 128 256 512; do
        sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# macOS ties the Accessibility grant to the signature. An ad-hoc signature ("-") changes with
# every build, so the grant has to be re-done after rebuilding. Set LEDGE_SIGN_IDENTITY to the
# name of a code-signing certificate (see README) to keep the grant across builds.
codesign --force --sign "${LEDGE_SIGN_IDENTITY:--}" --identifier app.ledge.Ledge "$APP"

echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x Ledge 2>/dev/null || true
    rm -rf /Applications/Ledge.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Ledge.app"
fi
