# Where Templeton Protect stands

Written 2026-08-31, at the end of the session that built the Mac app. Read this
with `NOTES.md` (the traps) and `docs/PRODUCT.md` (why the product is shaped this
way). This file is the state of things; the other two do not change often.

## In one paragraph

A signed, notarised, universal Mac app that scans the AI assistants installed on
a Mac for credentials left in conversation logs and for files other accounts can
read. It is installed at `/Applications/Templeton Protect.app` and there is a
distributable `mac/dist/Templeton Protect.dmg`. On Tony's machine a real scan
reads about 8,100 files across five installations and finds 4 critical, 1 worth
fixing, 10 minor. The scanning rules exist twice — TypeScript in `src/` (the CLI
and the tests) and Swift in `mac/Sources/ProtectCore/` (what the app runs).

## ⚠️ The app is behind the CLI, and it matters

**The Swift rules still offer only "Delete this transcript."** The TypeScript
rules were changed on 2026-08-31 (commits `c92aad9`, `5a609e2`) to do the right
thing instead:

- `redactKeys()` replaces each key-shaped value in place with
  `[<vendor> key removed by Templeton Protect]`, leaving the rest of the file
  byte for byte. The fix is labelled "Remove the key from this transcript".
- `ROTATE_AT` names the page where each vendor's keys are rotated, next to the
  button, because rotating is the actual fix and taking the key out of the file
  is only the clean-up.

Tony's own words on why: *"if it surfaces something like an openai key in a
transcript, how can we delete the entire session from their folders? that would
be incredibly destructive."*

So the signed app currently ships the destructive option he objected to, and none
of the rotation guidance. **Porting `redactKeys` and `ROTATE_AT` into
`mac/Sources/ProtectCore/` is the first thing to do.** The TypeScript suite (14
tests) already pins the behaviour to copy.

## What was built, in order

1. TypeScript engine and CLI — `src/`, 14 tests.
2. Native SwiftUI app. Not the planned `WKWebView` shell: the rules were ported
   to Swift, so the app is one binary with no server to start and no port to
   collide. TG-283.
3. Design pass against Tony's four colours — Midnight Navy ground, Champagne
   accent, Dusty Rose for trouble, Pearl White ink. Icon is the shared
   Radiant/AiOS swirl, champagne body with a navy swirl.
4. An opening screen that reads the machine before you press anything: the
   installations, their paths, file counts, and the three checks the scanner
   actually performs.
5. A scanning screen modelled on CleanMyMac's: the stage being read expands with
   the live file name, finished stages collapse to a result tile, and there is a
   Stop button. No percentage — the scanner cannot know the total before it walks
   the tree.
6. Export to PDF, CSV and Markdown. Every export runs through `redact()`.
7. Signed, notarised, stapled, universal. `mac/release.sh`. TG-285.

## Open

| What | Where |
|---|---|
| Port `redactKeys` + `ROTATE_AT` to Swift — see above | this file |
| Scan code, not just AI installations — half the tagline is unbuilt | `docs/PRODUCT.md` |
| Where the DMG is hosted, and how it updates | TG-286 |
| Tony to rotate the keys the scan found | TG-281 |
| Repo public/private, and the licence split | TG-282 |
| A Swift test target — Xcode is installed now, the old note was stale | `mac/Package.swift` |

## Not accidents

- **No percentage during the scan.** The total is unknown until the walk is done,
  and a fake percentage that stalls is worse than none.
- **A stopped scan keeps what it found.** Throwing it away makes Stop feel like a
  punishment.
- **Glass only on controls, never on content.** Apple's guidance, and the first
  version broke it everywhere.
- **The export destination always comes from a save panel.** Writing a file full
  of someone's paths into Downloads unasked is the sort of thing this app warns
  people about.

## Another agent works this repo

Commits from `tonyricciardi@TonysHomeMBPM4...` are a second agent on another
machine. It wrote the redaction work above. Check `git log` before assuming the
Swift and TypeScript sides still match, and never revert or overwrite its work.
