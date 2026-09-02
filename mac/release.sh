#!/usr/bin/env bash
# Build, sign, notarise and package Templeton Protect for distribution.
#
# ⚠️ THIS IS NOT build.sh WITH EXTRA STEPS. build.sh makes something that runs on
# THIS Mac. Anywhere else, an unsigned app is refused by Gatekeeper outright, and
# a security product whose first instruction is "override your security warning"
# has lost the argument before it starts.
#
#   ./release.sh            build, sign, notarise, staple, package
#   ./release.sh --no-notary  stop after signing (fast, for local checking)
#
# Needs: a "Developer ID Application" certificate in the login keychain, and a
# notarytool keychain profile. Create the profile once with:
#   xcrun notarytool store-credentials AC_PASSWORD \
#     --apple-id <apple-id> --team-id 5VY66S6G3M --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${PROTECT_IDENTITY:-Developer ID Application: Anthony Ricciardi (5VY66S6G3M)}"
PROFILE="${PROTECT_NOTARY_PROFILE:-AC_PASSWORD}"
APP="dist/Templeton Protect.app"
DMG="dist/Templeton Protect.dmg"
NOTARISE=1
[ "${1:-}" = "--no-notary" ] && NOTARISE=0

# ⚠️ THE CLAIMS ARE CHECKED BEFORE THE BUILD, NOT AFTER. A release is the moment
# the landing page and the engine are supposed to agree; catching the drift after
# notarising means either shipping a wrong number or throwing away ten minutes.
# Non-blocking on purpose — a missing site checkout must not stop a release.
if [ -x ../scripts/verify-claims.sh ]; then
  echo "▸ verifying the page's claims"
  ../scripts/verify-claims.sh 2>&1 | sed 's/^/  /' || \
    echo "  !! a landing-page claim does not reproduce — see above" >&2
fi

echo "▸ building universal"
# ⚠️ BOTH ARCHITECTURES. swift build defaults to this machine's, so the app was
# arm64-only — it would not launch at all on an Intel Mac, and that is a silent
# failure for the customer, not a warning for us.
swift build -c release --arch arm64 --arch x86_64 --product Protect

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/Protect "$APP/Contents/MacOS/Protect"
cp Info.plist "$APP/Contents/Info.plist"
cp Protect.icns "$APP/Contents/Resources/Protect.icns"
cp Resources/index.html "$APP/Contents/Resources/index.html"
cp Resources/swirl.png "$APP/Contents/Resources/swirl.png"
cp Resources/swirl-mark.png "$APP/Contents/Resources/swirl-mark.png"
cp Resources/templeton-tech.png "$APP/Contents/Resources/templeton-tech.png"
cp Resources/protect-lockup.png "$APP/Contents/Resources/protect-lockup.png"

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

lipo -info "$APP/Contents/MacOS/Protect" | sed 's/^/  /'

# ⚠️ STRIP EXTENDED ATTRIBUTES FIRST. codesign refuses a bundle carrying resource
# forks or Finder info — "detritus not allowed" — and the assets pick those up
# simply by having been copied around the filesystem.
xattr -cr "$APP"

echo "▸ signing"
# --options runtime is the hardened runtime, which notarisation requires.
# --timestamp gets a trusted timestamp, so the signature outlives the cert.
# ⚠️ SIGN INSIDE-OUT. Sparkle is not one binary: the framework carries two XPC
# services, an Autoupdate helper and an Updater.app, and codesign will not reach
# them by signing the outer bundle. Unsigned nested code is a notarisation
# rejection at best and, for the component that replaces this app on disk,
# exactly the thing that must not be left unverified. --deep is Apple's own
# "do not use this" flag; naming each piece is the supported way.
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  for nested in \
    "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE_FW/Versions/B/Updater.app" \
    "$SPARKLE_FW/Versions/B/Autoupdate"; do
    [ -e "$nested" ] && codesign --force --options runtime --timestamp \
                                 --sign "$IDENTITY" "$nested"
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_FW"
fi

codesign --force --options runtime --timestamp \
         --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
# ⚠️ VERIFY THE NESTED CODE TOO, or the first thing you learn about a bad
# signature is a notary rejection ten minutes later.
codesign --verify --strict --verbose=2 "$SPARKLE_FW" 2>&1 | sed 's/^/  /'

# ⚠️ NOTARISE THE APP FIRST, THEN BUILD THE IMAGE AROUND THE STAPLED COPY. The
# obvious order — package, notarise the image, then staple both — silently
# produces a disk image whose app has no ticket, because the copy inside the
# image was taken before the staple happened. Stapling "$APP" afterwards staples
# the one in dist/, not the one a customer drags to their Applications folder.
#
# It looks fine: Gatekeeper accepts the app off the mounted image, because the
# image's own ticket covers it. What it costs you is the case that ticket was
# for — the app dragged out of the image and launched somewhere the notary
# service cannot be reached. Caught by mounting a quarantined copy and running
# `stapler validate` on the app inside it, which is the only check that shows it.
if [ "$NOTARISE" = "1" ]; then
  echo "▸ notarising the app (this takes a few minutes)"
  # notarytool will not take a .app directly; it takes an archive of one.
  ZIP="$(mktemp -d)/Protect.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait | sed 's/^/  /'
  rm -rf "$(dirname "$ZIP")"
  echo "▸ stapling the app"
  xcrun stapler staple "$APP"
fi

echo "▸ packaging"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Templeton Protect" -srcfolder "$STAGE" \
               -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$NOTARISE" = "1" ]; then
  # ⚠️ THE IMAGE NEEDS ITS OWN ROUND. A ticket is tied to the hash of the thing
  # it was issued for, so rebuilding the image around the stapled app leaves the
  # image itself uncovered. This second submission is quick — everything inside
  # is already notarised — and it is what lets the image open offline.
  echo "▸ notarising the disk image"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | sed 's/^/  /'
  echo "▸ stapling the disk image"
  xcrun stapler staple "$DMG"
fi

echo "▸ verifying the way Gatekeeper will"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/  /' || true

if [ "$NOTARISE" = "1" ]; then
  # ⚠️ CHECK THE APP INSIDE THE IMAGE, WITH THE QUARANTINE FLAG SET. Everything
  # above this line passed on a release whose packaged app carried no ticket at
  # all. Anything arriving from a browser has that flag and it is what Gatekeeper
  # actually reacts to, so this is the only step here that tests what a customer
  # gets rather than what is sitting in dist/.
  echo "▸ verifying what a customer downloads"
  QT="$(mktemp -d)/Templeton Protect.dmg"
  cp "$DMG" "$QT"
  xattr -w com.apple.quarantine "0083;00000000;Safari;" "$QT"
  MOUNT="$(hdiutil attach "$QT" -nobrowse -readonly | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')"
  spctl --assess --type execute --verbose=4 "$MOUNT/Templeton Protect.app" 2>&1 | sed 's/^/  /'
  xcrun stapler validate "$MOUNT/Templeton Protect.app" 2>&1 | sed 's/^/  /'
  # ⚠️ DETACH IS FLAKY AND `set -e` MAKES THAT FATAL. The volume is often still
  # busy for a moment after spctl and stapler have read it, so hdiutil returns
  # 16 and the whole release dies here — after a perfectly good signed, stapled
  # disk image exists, but BEFORE the appcast is written. Twice that produced a
  # valid DMG behind a stale feed, and twice it was misread as something else
  # (Apple hanging, then a killed process group). Retry, then force, and never
  # let it end the run.
  for attempt in 1 2 3 4 5; do
    hdiutil detach "$MOUNT" -quiet && break
    sleep 2
    [ "$attempt" = 5 ] && hdiutil detach "$MOUNT" -force -quiet
  done || true
  rm -rf "$(dirname "$QT")" || true
fi

# ── the appcast: how a copy already out there learns this exists ──────────
#
# ⚠️ A RELEASE NOBODY CAN RECEIVE IS NOT A RELEASE. Until this step existed,
# every version reached exactly one Mac — the one with the build tools on it.
# generate_appcast signs each update with the EdDSA key in the login keychain
# and writes the XML Sparkle reads; the private key never touches the repo.
#
# ⚠️ THE DMG IS 2 MB, WHICH IS WHY THIS CAN BE AUTOMATIC. Radiant's is 163 MB
# and has to be uploaded by hand to Hostinger because git refuses anything over
# 100 MB. Protect's rides the repo like any other file, so publishing is a push.
SITE="${PROTECT_SITE_REPO:-$HOME/Projects/templeton-group-dev-website}"
PAGE="$SITE/showcase/protect"
GEN="$(find .build/artifacts -maxdepth 6 -type f -name generate_appcast | head -1)"

if [ -n "$GEN" ] && [ -d "$SITE" ]; then
  echo "▸ appcast"
  mkdir -p "$PAGE"
  # generate_appcast reads a directory of archives and emits appcast.xml beside
  # them, keeping older entries so somebody two versions behind still updates.
  STAGE="$(mktemp -d)"
  cp "$DMG" "$STAGE/"
  [ -f "$PAGE/appcast.xml" ] && cp "$PAGE/appcast.xml" "$STAGE/appcast.xml"
  "$GEN" --download-url-prefix "https://www.templetongroup.dev/showcase/protect/" \
         "$STAGE" 2>&1 | sed 's/^/  /'
  cp "$STAGE/appcast.xml" "$PAGE/appcast.xml"
  cp "$DMG" "$PAGE/Templeton Protect.dmg"
  # The landing page reads this to show the current version without a rebuild.
  SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
  printf '{\n  "version": "%s",\n  "size": "%s"\n}\n' "$VERSION" "$SIZE" > "$PAGE/version.json"
  rm -rf "$STAGE"
  echo "  staged $PAGE — commit and push that repo to publish"
else
  echo "!! appcast skipped (no generate_appcast, or site repo not at $SITE)" >&2
fi

echo "▸ done: $DMG"
