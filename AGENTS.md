## Templeton Protect — read this first

⚠️ **THIS IS ITS OWN PROJECT, IN ITS OWN CHAT.** Split out 2026-08-31. It was
built inside an AiOS conversation, which meant AiOS's rules — its branch model,
its deploy story, its two-tenant split — were being applied to a standalone Mac
app they do not describe. AiOS lives at `~/Projects/aios` with its own
`AGENTS.md`. A finding in one is not automatically true in the other.

Start every turn by reading **`HANDOFF.md`** — where things stand, what is open,
and what the app is currently getting wrong — then **`NOTES.md`**. It is short and every line is
something that already went wrong: the decorative view that sized the whole
window, glass losing its tint when the window is not frontmost, the swirl mask
floor, the `osascript` call that hangs on an accessibility prompt, and how to
install without destroying the installed app.

⚠️ **A SECOND AGENT WORKS THIS REPO** from another machine. Run `git log` before
assuming the Swift and TypeScript rule sets still match, and never revert or
overwrite its work.

### What this is

A Mac app that runs three scans and collects the findings into one list: the
Mac's own security posture, the AI assistants installed on it, and a codebase you
point it at. Read-only until you ask it to fix something. It is sold three ways:
bundled with paid AiOS plans, as a subscription, and as an open-source download.
`docs/PRODUCT.md` holds the product shape and the decisions behind it.

The tagline is "Scan your Mac, your assistants, and your code" and as of
2026-08-31 all three exist **in the Swift engine only**.

### Where things are

| What | Where |
|---|---|
| Scan rules (Swift — what the app runs) | `mac/Sources/ProtectCore/` |
| Hardware and posture scan | `mac/Sources/ProtectCore/Machine.swift` |
| Codebase scan | `mac/Sources/ProtectCore/Code.swift` |
| Remediation steps and key-rotation pages | `mac/Sources/ProtectCore/NextSteps.swift` |
| The app | `mac/Sources/Protect/` |
| Scan rules (TypeScript — the CLI and the tests) | `src/` |
| Local build | `mac/build.sh` |
| Signed, notarized release | `mac/release.sh` |
| Tests | `npm test` (installations rules only) |
| Harness for the unpinned Swift rules | `mac/Sources/Probe` |

⚠️ **THE TWO RULE SETS NO LONGER MATCH.** They were the same logic written twice
and the TypeScript suite pinned the behavior. As of 2026-08-31 the hardware and
code scans exist in Swift alone, so `npm test` pins the installations rules and
nothing else. See `HANDOFF.md`; closing this is the largest open item.

### How to work

- **Verify on the running app, not in the source.** Tests did not catch one of
  the problems listed in `NOTES.md`. Build it, launch it, screenshot it.
- **Never hand Tony a terminal command to repair a shipped app.** It has to fix
  itself, and it must never show a message with no button.
- **Install by swapping, never by deleting first** — `rm` then `cp` once
  destroyed the installed app when the source was mid-rebuild.
- **A running app keeps its old Dock icon.** Quit and relaunch before deciding an
  icon change did not land.
- US English, not British. The test suite enforces it.
- Keep secrets and client content out of the notes and the commit messages.

### This conversation's history

Protect was built inside an AiOS chat, so that transcript holds both projects.
`tools/extract-session.py` lifts out the Protect half — it cuts at the turn where
the security-coworker thread begins and repairs the parent chain at the cut, so
the result reads as a conversation that starts there rather than a truncated one.

    python3 tools/extract-session.py \
      ~/.claude/projects/-Users-tonyricciardi-Projects-aios-claude/<session>.jsonl

⚠️ **Re-run it at the end of a session.** The source keeps growing while the chat
is open, so an extract taken mid-session stops where it was taken. It overwrites
its output rather than appending.

⚠️ **Switching a session's working directory moves its whole transcript** to the
new project folder — the AiOS half of that conversation vanished from the AiOS
project the moment Protect got its own. `--head` writes everything *before* the
marker, which is how that history goes back where it belongs:

    python3 tools/extract-session.py <session>.jsonl --head \
      --out-dir ~/.claude/projects/-Users-tonyricciardi-Projects-aios-claude

### Tracking

Linear, team **The Templeton Group**, project **Templeton Protect**. Linear is
the source of truth; nothing links git to it automatically, so file or update the
issue in the same turn as the work, and name it in the commit message — `Fixes
TG-nn` only when the work is finished *and* verified, `Ref TG-nn` otherwise.

### Before ending a turn

Update `NOTES.md` when something new goes wrong or a procedure changes. Update
the Linear issue. Commit and push. A task is not handed off until another agent
can resume it from `NOTES.md` alone.
