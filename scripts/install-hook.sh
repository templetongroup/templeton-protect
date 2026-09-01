#!/usr/bin/env bash
# Install Templeton Protect as a pre-commit hook in the current repository.
#
# ⚠️ IT SCANS, IT DOES NOT BLOCK BY DEFAULT. A hook that refuses a commit on a
# minor finding is a hook people delete in a week. This one fails the commit only
# on critical findings; loosen or tighten with --fail-on.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Not inside a git repository." >&2; exit 1
}

cli="$(command -v protect-cli || true)"
if [ -z "$cli" ]; then
  echo "protect-cli is not on PATH. Build it with:" >&2
  echo "  swift build -c release --product protect-cli" >&2
  echo "then copy .build/release/protect-cli somewhere on PATH." >&2
  exit 1
fi

hook="$root/.git/hooks/pre-commit"
cat > "$hook" <<HOOK
#!/usr/bin/env bash
# Installed by Templeton Protect.
protect-cli code --fail-on critical "\$(git rev-parse --show-toplevel)" || {
  echo
  echo "Templeton Protect found a critical issue. Commit blocked."
  echo "Fix it, or commit with --no-verify to override."
  exit 1
}
HOOK
chmod +x "$hook"
echo "Installed pre-commit hook at $hook"
echo "It blocks a commit only on critical findings. Edit --fail-on to change that."
