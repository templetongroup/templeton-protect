#!/usr/bin/env bash
# Build Templeton Protect.app.
#
# ⚠️ HAND-ASSEMBLED, like the AiOS app, because this machine has the Command Line
# Tools rather than full Xcode — no xcodebuild, no .xcodeproj. A .app is a
# directory with a plist and a binary in the right places, and that is enough.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Templeton Protect.app"
swift build -c release --product Protect

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Protect "$APP/Contents/MacOS/Protect"
cp Info.plist "$APP/Contents/Info.plist"
cp Protect.icns "$APP/Contents/Resources/Protect.icns"
# ⚠️ THE UI IS A RESOURCE, NOT A FILE ON DISK SOMEWHERE. Loading it from the
# bundle is what makes the app self-contained — move it anywhere and it works.
cp Resources/index.html "$APP/Contents/Resources/index.html"
cp Resources/swirl.png "$APP/Contents/Resources/swirl.png"

# Ad-hoc signing so Gatekeeper will run it locally. A Developer ID and
# notarization are needed before it goes to anybody else — see TG-283.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "built: $APP"
