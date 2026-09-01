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
cp Resources/swirl-mark.png "$APP/Contents/Resources/swirl-mark.png"
cp Resources/templeton-tech.png "$APP/Contents/Resources/templeton-tech.png"

# ⚠️ SwiftPM DOES NOT COMPILE .metal FILES. Declaring them as a resource copies
# the SOURCE into the bundle and nothing else — `ShaderLibrary.default` then
# finds no library and every effect silently does nothing, which is the worst
# kind of failure: it looks like a design choice. Metal is compiled here, by
# hand, into the default.metallib that ShaderLibrary actually looks for.
if ls Sources/Protect/Shaders/*.metal >/dev/null 2>&1; then
  AIR="$(mktemp -d)"
  for m in Sources/Protect/Shaders/*.metal; do
    xcrun -sdk macosx metal -c "$m" -o "$AIR/$(basename "${m%.metal}").air" || exit 1
  done
  xcrun -sdk macosx metallib "$AIR"/*.air -o "$APP/Contents/Resources/default.metallib" || exit 1
  rm -rf "$AIR"
fi


# ⚠️ SPARKLE IS A FRAMEWORK AND HAS TO TRAVEL INSIDE THE BUNDLE. The binary
# links it by rpath (@executable_path/../Frameworks, set in Package.swift); with
# the framework missing the app builds cleanly and then dies at launch with
# "image not found". Copied with -R to keep the symlinks a framework needs.
SPARKLE="$(find .build/artifacts -maxdepth 6 -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)"
if [ -n "$SPARKLE" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
  cp -R "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
else
  echo "!! Sparkle.framework not found — run: swift package resolve" >&2
  exit 1
fi


# Ad-hoc signing so Gatekeeper will run it locally. A Developer ID and
# notarization are needed before it goes to anybody else — see TG-283.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "built: $APP"
