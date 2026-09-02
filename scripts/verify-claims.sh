#!/usr/bin/env bash
# Every number on the landing page, recomputed from the source it describes.
#
# ⚠️ THIS EXISTS BECAUSE ONE OF THEM WAS WRONG. The page shipped a draft
# claiming 16 credential vendors when the real figure was 12 — the regex tuples
# had been counted, and the redaction list repeats several. Nobody would have
# noticed, and a false number on a security scanner's own marketing page is
# precisely the thing the product exists to catch. The discipline is borrowed
# from T3MP3ST's `verify-claims`: a claim that cannot be reproduced does not
# ship.
#
#   scripts/verify-claims.sh            check the published page
#   scripts/verify-claims.sh --print    just show the computed numbers
#
# Exits non-zero on any mismatch, so it can gate a release.
set -uo pipefail
cd "$(dirname "$0")/.."

CORE="mac/Sources/ProtectCore"
PAGE="${PROTECT_SITE_REPO:-$HOME/Projects/templeton-group-dev-website}/showcase/protect/index.html"

rules=$(grep -rhoE 'rule: "[a-z-]+"' "$CORE"/*.swift | sort -u | wc -l | tr -d ' ')
vendors=$(python3 scripts/count-vendors.py "$CORE")
assistants=$(grep -c 'AiHome(tool:' "$CORE/Scan.swift" | tr -d ' ')

# ⚠️ THE ZERO IS THE LOAD-BEARING CLAIM. "Nothing leaves this Mac" is the whole
# trust position, so it is checked as an absence rather than asserted: no HTTP
# client anywhere in the scanning engine. Sparkle's update check lives in the app
# target, not here, and the page says so in the line beneath the number.
egress=$(grep -rlE 'URLSession|NSURLConnection|CFHTTP' "$CORE"/*.swift 2>/dev/null | wc -l | tr -d ' ')

if [ "${1:-}" = "--print" ]; then
  printf 'rules      %s\nvendors    %s\nassistants %s\negress     %s\n' \
         "$rules" "$vendors" "$assistants" "$egress"
  exit 0
fi

if [ ! -f "$PAGE" ]; then
  echo "!! landing page not found at $PAGE" >&2
  echo "   set PROTECT_SITE_REPO if the site repo lives elsewhere" >&2
  exit 2
fi

fail=0
check() {  # label-keyword  computed-value  display-name
  local got
  got=$(python3 scripts/read-claim.py "$PAGE" "$1")
  if [ "$got" = "$2" ]; then
    printf '  ok    %-12s %s\n' "$3" "$2"
  else
    printf '  FAIL  %-12s page says %s, source says %s\n' "$3" "$got" "$2"
    fail=1
  fi
}

echo "verifying claims against $PAGE"
check "rules"      "$rules"      rules
check "vendors"    "$vendors"    vendors
check "assistants" "$assistants" assistants
check "bytes"      "$egress"     egress

if [ "$fail" = 0 ]; then
  echo "all claims reproduce from source"
else
  echo "a claim on the page does not reproduce — fix the page, or the count" >&2
fi
exit "$fail"
