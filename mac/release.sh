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
lipo -info "$APP/Contents/MacOS/Protect" | sed 's/^/  /'

# ⚠️ STRIP EXTENDED ATTRIBUTES FIRST. codesign refuses a bundle carrying resource
# forks or Finder info — "detritus not allowed" — and the assets pick those up
# simply by having been copied around the filesystem.
xattr -cr "$APP"

echo "▸ signing"
# --options runtime is the hardened runtime, which notarisation requires.
# --timestamp gets a trusted timestamp, so the signature outlives the cert.
codesign --force --options runtime --timestamp \
         --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

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
  echo "▸ notarising (this takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | sed 's/^/  /'
  echo "▸ stapling"
  # ⚠️ STAPLE BOTH. The ticket on the disk image lets it open offline; the one
  # inside the app is what survives being dragged out of the image.
  xcrun stapler staple "$APP"
  xcrun stapler staple "$DMG"
fi

echo "▸ verifying the way Gatekeeper will"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/  /' || true
echo "▸ done: $DMG"
