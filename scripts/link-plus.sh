#!/usr/bin/env bash
# Wire a local checkout of the private Protect+ repo into this one — or unwire it
# with `--off`, which is how you check that the free build still stands alone.
#
# ⚠️ SYMLINKS, NOT COPIES. Two copies of the paid layer drift, and the one you
# are not looking at is the one that ships. The Plus folders are gitignored here,
# so nothing from the private repo can be committed to the public one by accident.
set -euo pipefail
cd "$(dirname "$0")/.."

CORE=mac/Sources/ProtectCore/Plus
APP=mac/Sources/Protect/Plus

# ⚠️ CLEARING THIS IS NOT OPTIONAL. PROTECT_PLUS is decided by hasPlus() while
# the manifest is being evaluated, and SwiftPM caches manifests by *content* —
# so `touch Package.swift` does nothing, and the build keeps using whichever
# answer it got first. The failure looks like ordinary missing-member errors
# ("cannot find 'Resident' in scope", "Model has no member licenceError"), which
# sends you hunting through the guards instead of at the cache. Two separate
# hours went into that, once in each direction.
bust_cache() { rm -rf mac/.build/manifest.db mac/.build/manifests ~/.swiftpm/cache/manifests; }

if [ "${1:-}" = "--off" ]; then
  rm -rf "$CORE" "$APP"; bust_cache
  echo "unlinked. swift build now produces the free app."
  exit 0
fi

PLUS="${PROTECT_PLUS_REPO:-$HOME/Projects/templeton-protect-plus}"
[ -d "$PLUS" ] || { echo "private repo not found at $PLUS" >&2; exit 1; }

for pair in "ProtectCore:$CORE" "Protect:$APP"; do
  src="$PLUS/${pair%%:*}"; dst="${pair##*:}"
  rm -rf "$dst"; mkdir -p "$dst"
  for f in "$src"/*.swift; do ln -sf "$f" "$dst/$(basename "$f")"; done
  echo "  $dst → $(ls "$dst" | tr '\n' ' ')"
done
bust_cache
echo "linked. swift build now defines PROTECT_PLUS."
