# Where Templeton Protect stands

Updated 2026-08-31, at the end of the session that added the other two scans.
Read this with `NOTES.md` (the traps) and `docs/PRODUCT.md` (why the product is
shaped this way). This file is the state of things; the other two change less.

## In one paragraph

A signed, notarized, universal Mac app that runs **three scans** and collects
their findings into one list: the Mac's own hardware and security posture, the AI
assistants installed on it, and a codebase you point it at. It is installed at
`/Applications/Templeton Protect.app` and there is a distributable
`mac/dist/Templeton Protect.dmg`. On Tony's machine a full run reads about 9,800
files and settings and reports 7 critical, 7 worth fixing, 11 minor.

## What changed on 2026-08-31

### The opening screen is three cards

Tony: *"i think the initial screen should have 3 components: 1. Scan your
Hardware… 2. Scan your Installations… 3. Scan your code."* Each card names what
it will do and shows something already true about this Mac before anything is
pressed — the model and chip, the assistants found, the folder chosen. Findings
accumulate into one list rather than three reports.

- **Scan your hardware** — `Machine.swift`. FileVault, SIP, Gatekeeper, the
  firewall, Remote Login / Screen Sharing / File Sharing / Remote Management,
  every port listening on a non-loopback address, guest account, automatic login,
  password-on-wake, automatic security updates, and whether the Mac ever sleeps
  or locks. That last group exists because of what this product is for: a Mac
  held awake and unlocked so an agent can finish a long job is a different
  machine from the one its owner thinks they have. Findings that need an
  administrator get a button that opens the exact System Settings pane — the app
  does not flip system switches on anyone's behalf.
- **Scan your installations** — unchanged, the scan that already worked.
- **Scan your code** — `Code.swift`. A folder chosen in an open panel. Keys
  committed to the repository, `.env` files git is not ignoring, `.env` templates
  with real values in them, private keys in the tree, secrets files git is
  already tracking, a token embedded in a git remote, and five code shapes that
  are wrong every time they appear.

### The transcript fix is redaction, at last

This was the top open item and it is closed. The button reads **"Remove the key
from this transcript"** and replaces each key-shaped value in place with
`[<vendor> key removed by Templeton Protect]`, leaving the rest of the
conversation byte for byte. `redactKeys` and `rotateAt` are ported from the
TypeScript engine; the two sides match again.

### "Next: …" pointed nowhere, and now it works

Tony, looking at the shipped app: *"they point nowhere and are meaningless."* He
was right — it was plain yellow text naming a folder under `skills/` that is not
bundled in the app, and which turns out to be an enterprise runbook about Active
Directory. Findings now carry real steps that expand in place, with the vendor's
own key page as a button that opens it. And each disclosure opens under its own
toggle, which it did not at first: *"when i click the What was found text, it
opens below the Yellow text. hard to follow."*

## ⚠️ The TypeScript engine is now behind the Swift one

The two rule sets were "the same logic written twice" and that is **no longer
true**. `src/` has the installations scan only; the hardware and code scans exist
in Swift alone, which means:

- The 14 TypeScript tests pin the installations rules and nothing else. Every
  rule in `Machine.swift` and `Code.swift` is unpinned, verified by running
  `mac/Sources/Probe` and reading the output.
- The CLI (`node --experimental-strip-types src/cli.ts`) does not scan hardware
  or code.

Closing this is a real piece of work and it is the largest open item. The code
scan is the half worth porting first — it is cross-platform and it is the half of
the tagline that reaches people who run neither Claude nor Codex. The hardware
scan is macOS-specific shell-outs and porting it may be duplication for its own
sake; worth a decision rather than an assumption.

## Open

| What | Where |
|---|---|
| TypeScript parity — see above; the largest open item | TG-291 |
| A Swift test target — Xcode is installed, `Probe` is not a test suite | TG-291 |
| Whether `skills/` stays now that no finding links to it | `skills/NOTICE` |
| Where the DMG is hosted, and how it updates | TG-286 |
| Tony to rotate the keys the scan found | TG-281 |
| Repo public/private, and the license split | TG-282 |
| The `.env.local.bak-*` files the code scan found in `~/Projects/aios` | TG-281 |

## Not accidents

- **No percentage during a scan.** The total is unknown until the walk is done,
  and a fake percentage that stalls is worse than none.
- **A stopped scan keeps what it found.** Throwing it away makes Stop a
  punishment.
- **Glass only on controls, never on content.** Apple's guidance, and the first
  version broke it everywhere.
- **The export destination always comes from a save panel**, and the code folder
  always comes from an open panel. Reading somebody's source tree, or writing a
  file full of their paths, is not something to do without being pointed.
- **A finding never leaves somebody with a sentence and no button** — which is
  why machine findings open the settings pane rather than printing a `sudo` line.

## Another agent works this repo

Commits from `tonyricciardi@TonysHomeMBPM4…` are a second agent on another
machine; it wrote the TypeScript redaction work this session ported. Check
`git log` before assuming the two rule sets match, and never revert or overwrite
its work.
