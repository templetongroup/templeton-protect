# Templeton Protect — working notes

Read this before changing the Mac app. Every line is something that already went
wrong and cost real time.

## Where things are

| What | Where |
|---|---|
| Hardware and posture scan (Swift only) | `mac/Sources/ProtectCore/Machine.swift` |
| Codebase scan (Swift only) | `mac/Sources/ProtectCore/Code.swift` |
| Remediation steps and key-rotation pages | `mac/Sources/ProtectCore/NextSteps.swift` |
| Scan rules (Swift, what the app runs) | `mac/Sources/ProtectCore/` |
| The app | `mac/Sources/Protect/` |
| Scan rules (TypeScript, the CLI and the tests) | `src/` |
| Build the app | `mac/build.sh` → `mac/dist/Templeton Protect.app` |
| Icon generator | `mac/make-icon.py` |
| Bundled assets (swirl, Templeton mark) | `mac/Resources/`, copied by `build.sh` |
| Tests | `npm test` (10, TypeScript) |

The Swift and TypeScript rule sets are the same logic written twice. There is no
Swift test target — this machine has the Command Line Tools, not full Xcode, so
XCTest is absent. `mac/Sources/Probe` is the scratch executable for measuring
Swift behaviour against the real filesystem.

## The three scans

Added 2026-08-31. The opening screen is three cards; each runs its own scan and
the findings collect into **one list**, because somebody with a key in a
transcript, a firewall that is off and an `.env` committed to a repository has
one problem — this Mac — not three reports to reconcile.

- ⚠️ **`ScanResult.filesRead` is not always files.** The hardware scan reads
  fifteen settings and no files at all. Both exports said "Checked 15 files
  across This Mac" until this was caught; they say "files and settings" now, and
  the scanning screen's counter says "checks run" when `model.active == .machine`.
- ⚠️ **A finding's identity is `layer/rule/where`, not the path.** Three scans
  share one list and the path was doing double duty as the SwiftUI list id and
  the key for fix outcomes. Two findings about the same file — a key in it and
  its being readable — collapsed into one row, and a fix applied to either
  reported its result on both.
- ⚠️ **The open panel is what authorizes a fix outside the AI homes.**
  `insideScannedTree` refused every fix the code scan offers until it learned
  about the chosen folder; the folder is passed in as `extraRoots` rather than
  the guard being widened.

### The hardware scan

Every check is a query a normal account can answer — nothing prompts for a
password, because a scanner that opens an admin prompt on launch is one nobody
runs twice.

- ⚠️ **Read the pipe before waiting on the process.** A pipe holds ~64 KB;
  `netstat -an` on a working Mac is past that, so `waitUntilExit()` first
  deadlocks on exactly the machines this app is for. Every subprocess also has a
  deadline, and no subprocess is ever `osascript`.
- ⚠️ **Not `launchctl print-disabled`.** It reports the *override*, so a service
  nobody has ever touched reads back "enabled" whether it is running or not —
  every early version said SSH was on for every Mac. `launchctl print
  system/<label>` exiting 0 is the real answer.
- ⚠️ **`system_profiler` output is copied by allowlist, never filtered.** It
  prints the serial number, the hardware UUID and the provisioning UDID next to
  the four fields we want. A denylist leaks the day Apple adds a field, and this
  app puts its screen on a projector and writes PDFs people email.
- ⚠️ **Never name a service from a port number alone.** Port 5000 was reported as
  "a local model server"; it is AirPlay Receiver, which macOS turns on itself.
  Ports 3000 and 8080 are whatever somebody started this morning. `lsof` names
  the process (it only sees this account's, which is why `netstat` still decides
  the list), and the port table holds four unambiguous entries.
- ⚠️ **Do not report a port that already has its own finding.** 22, 5900 and 3283
  are Remote Login, Screen Sharing and Remote Management, each with its own card
  and its own button. Listing them again under "programs listening" turns one
  problem into two and makes the list look padded.
- ⚠️ **`NSWorkspace.open` returns true for any `x-apple.systempreferences:` URL.**
  System Settings claims the scheme, so it launches whether or not the pane
  identifier means anything — which means the obvious "try the modern id, fall
  back to the legacy one" design silently drops people on the front page and
  reports success. The pane is chosen by macOS version instead. Found by opening
  it and looking, not by reading the return value.

### The code scan

Points at a folder chosen in an `NSOpenPanel`. Everything it reports is anchored
to a byte pattern, a file mode or an answer from git — never to a judgement.

⚠️ **Every one of these was a false positive on the first run, and each is the
kind that makes somebody close the app:**

- A repo's own test fixtures reported as a critical credential leak. Test files
  are reported *quietly* now, not suppressed — a real key pasted into `tests/` is
  committed like any other, and `tests/` is where nobody looks.
- `.env.example` reported as a gitignore mistake. It is *meant* to be committed.
  The only thing wrong with a template is a real key in it, and that one is
  critical because a template is committed on purpose.
- `\`Could not delete it: ${err}\`` reported as SQL injection. Matching
  `select|insert|update|delete` plus an interpolation finds every template string
  in the codebase containing a verb; the rule needs the *statement* — `SELECT …
  FROM`, `DELETE FROM`.
- `--insecure` and `exec(Sync)` — matched inside this scanner's own rule list.
  `--insecure` now needs `curl` or `wget` on the same line; the bare `exec(` arm
  is gone.
- `eval(str)` inside a minified bundle in `.next-verify/`. Adding one more name
  to the skip list only closes the case somebody already hit; generated files are
  detected **by shape** — bytes per line over 400 — and skipped for the pattern
  rules. Keys are still read out of them, because a credential in a bundle has
  shipped to every browser that loaded it.

## Next steps, and the yellow line that pointed nowhere

Every finding used to end with `Next: How to rotate a leaked key properly` — the
title of a folder under `skills/`, in plain yellow text, not a button, naming a
document that is not bundled in the app. Tony, in the shipped app: *"they point
nowhere and are meaningless."*

- ⚠️ **A label that names help nobody can reach is worse than no label**, because
  it looks like help. The steps live in `NextSteps.swift` now: a title, ordered
  plain-language steps, and the vendor's own key page as a button that opens it.
- ⚠️ **Only vendors whose page is known get a link.** A plausible-looking URL that
  404s is the same failure one step later.
- ⚠️ **A disclosure's content goes directly under its own toggle.** "What was
  found" rendered at the bottom of the card, below the next-steps section, so
  opening it made text appear under a different heading. Tony: *"when i click the
  What was found text, it opens below the Yellow text. hard to follow."*

## The fix for a key in a transcript

⚠️ **Remove the key, not the transcript.** The app shipped signed and notarized
offering `Delete this transcript` as the only option. Tony: *"if it surfaces
something like an openai key in a transcript, how can we delete the entire
session from their folders? that would be incredibly destructive."*

`redactKeys` in `NextSteps.swift` replaces each key-shaped value with
`[<vendor> key removed by Templeton Protect]` and leaves the rest byte for byte.
This is the Swift half of the change the TypeScript engine took the same day —
**the two must not drift again.**

- ⚠️ **Write beside it and rename.** Truncating the real file and refilling it
  leaves somebody's conversation half destroyed if the write is interrupted,
  which is the exact outcome the fix exists to avoid.
- ⚠️ **Confirm it took.** Re-read the file and re-run `findKeys`. Telling somebody
  a key is gone while it is still on disk is worse than not offering the fix.
- Placeholders survive, unicode survives, the line count is unchanged, and a
  target outside the scanned tree is still refused. Measured, not assumed.
- The narrower `keyShapesForRedaction` list is deliberate: a
  `-----BEGIN PRIVATE KEY-----` match is one line of a multi-line block, so
  replacing it leaves the body behind and produces a file that lies about being
  clean.

## Design

Four colours, chosen by Tony, and nothing outside them:

    Midnight Navy  #192A56   the ground
    Champagne      #F7D794   the one accent
    Dusty Rose     #EDA6A3   trouble
    Pearl White    #FCFBFB   the ink

Scales live in `mac/Sources/Protect/Design.swift` — spacing, type, opacity,
radius. Nothing picks a value outside them.

- ⚠️ **Glass belongs on controls, never on content.** Apple's macOS guidance puts
  Liquid Glass on navigation and controls and explicitly not on the content
  layer, and never stacked. Findings and tiles use `.contentSurface()`.
- ⚠️ **Glass drops its tint when the window is not frontmost.** The primary
  action was tinted glass and rendered as a plain grey disc whenever focus moved
  away. Primary actions are solid. Secondary glass controls carry a border so
  they still read as controls when the material goes quiet.
- ⚠️ **Severity is never carried by colour alone.** Rose and champagne are close
  in warmth and a red/green viewer separates them poorly. Every finding states
  its severity in words and carries an icon.
- ⚠️ **State the ink on every `Text`.** `preferredColorScheme` does not reach an
  `NSHostingView`'s default label colour: the one string without an explicit
  colour was the app's own title, and it rendered black on navy. The window is
  `darkAqua` as well, but do not rely on it.

## The scanning screen

`mac/Sources/Protect/Scanning.swift`, fed by `ScanProgress` from the scanner. The
stage being read expands and carries the live detail; finished stages collapse to
a tile holding their result; queued ones sit quiet. The layout moving *is* the
progress indicator — there is no percentage, because the scanner cannot know the
total before it walks the tree, and a fake percentage is worse than none.

- ⚠️ **The progress callback is throttled to 12/second.** It fires once per file
  read — thousands of times — and publishing every one repaints the window faster
  than it can draw, starving the scan of the CPU it is asking for.
- ⚠️ **Cancellation is an `NSLock`-backed flag, not actor-isolated state.** It is
  polled between files; hopping to the main actor 8,000 times to read a Bool
  costs more than the work it guards. Proved with `Probe`: cancelling at 300
  files returns 300 files and 1 finding against 8,121 and 15 for a full run, and
  keeps what it had found.
- ⚠️ **Split the display path, do not build a `URL` from it.** The scanner hands
  over a path beginning `~/`, and `URL(fileURLWithPath:)` resolves that back to
  `/Users/<name>/…` — so the screen showed the account name in a panel meant to
  be readable over your shoulder.
- `contentTransition` needs macOS 13 and this app runs on 12, so it is behind
  `#available`.

## Exports

`mac/Sources/ProtectCore/Export.swift` (CSV, Markdown) and `ExportPDF.swift`.
They live in the core, not the app, so `Probe` can run them against a real scan —
there is no Swift test target on this machine.

- ⚠️ **Every export runs through `redact()`.** A report carrying the key it found
  has copied that key somewhere new — a Downloads folder, an email, a ticket —
  which is the exact failure this tool exists to catch.
- ⚠️ **CSV is RFC 4180 quoted.** A path can contain a comma and evidence can
  contain a quote mark; either one unescaped shifts every later column under the
  wrong header, and the file still opens and still looks plausible.
- The destination always comes from an `NSSavePanel`. Writing a file full of
  paths into Downloads unasked is the sort of thing this app warns people about.
- The PDF is typeset with CoreText and paginates; headings never end a page. It
  carries the mark as a watermark, a summary band, severity dots in the gutter,
  paths in tinted boxes, and a footer with the page number.
- ⚠️ **The print palette is the screen palette darkened.** Champagne is invisible
  on paper and dusty rose is too light to read at 9pt. The darkened set is
  declared once at the top of `ExportPDF.swift` rather than reached for ad hoc.
- ⚠️ **The watermark is clipped-and-filled, not drawn.** The mark asset is white
  ink on transparency — right for the screen, and on white paper it produces
  exactly nothing, which is what the first version shipped. Use it as a mask and
  fill navy.

## Controls

⚠️ **`.frame()` ON A `Text` DOES NOT MAKE AN 84pt TARGET.** The Back button drew
an 84pt glass circle and only the letters responded to a click — the frame lays
the button out at that size, but there is nothing behind the text for SwiftUI to
hit-test, so the label's hit region stays the shape of the glyphs. Tony: *"that
back button is awkward in that it only works if you click exactly on the Back
text."* A control that looks like a large target and behaves like a small one is
worse than one that looks small, because the miss has no explanation. State the
region: `.contentShape(Circle())`, matching the shape you can see.

Measured on the running app rather than assumed: a click 35pt left of centre —
inside the circle, nowhere near a glyph — goes back; one 66pt above the centre,
outside the circle, does not. So the target is the circle, not an oversized
rectangle.

⚠️ **A click on a window that is not key activates it and the control never sees
the press.** Two runs of that test read as failures for this reason before the
window was brought forward first. A false negative from focus looks exactly like
a layout bug.

⚠️ **A control is one color or it is two things.** The first version put the
chevron in champagne and the word in pearl; Tony: *"the Back should also be in the
same yellow."* Half a control in the accent and half in the ink reads as two
elements that happen to sit near each other. The `foregroundStyle` goes on the
stack, not on each child.

## The footer

"Templeton Protect is a Templeton Technologies product" and the mark, linking to templetontech.com —
the same footer Radiant and AiOS carry, so the three read as one company's
products. The mark is `mac/Resources/templeton-tech.png`, copied from Radiant's
`public/templeton-tech.png`; keep them the same file. Opening the link uses
`NSWorkspace`, not a SwiftUI `Link`.

## The window

⚠️ **A decorative view with fixed-size children will size the whole window.**
`Aurora`'s circles and capsules are fixed at up to 1200pt. As a `ZStack` it
reported that as its own size, so the window's `ZStack` grew to about 870pt
against a 720pt window and centred itself — pushing roughly 75pt off the top and
putting the headline under the traffic lights.

Three separate attempts at a top inset — padding on the content, `safeAreaInset`,
padding on the scroll view — all measured **identically** at 13pt, because every
one of them was being applied above the visible edge of the window. What actually
found it: painting the inset red and measuring 125pt of a 200pt band on screen.

The fix is that decoration is an `.overlay` on the gradient, then `.clipped()`.
An overlay does not vote on its parent's size.

The window is `.fullSizeContentView`, so content starts at y=0 under the traffic
lights; `Chrome.titleBar` reserves the strip. Measured: the content view is the
full window and `contentLayoutRect` is 32pt shorter.

## Verifying

Look at the running app. Tests did not catch a single one of the problems above.

    mac/build.sh
    PROTECT_AUTOSCAN=installations "mac/dist/Templeton Protect.app/Contents/MacOS/Protect"

`PROTECT_AUTOSCAN=machine|installations|code` runs a real scan on launch so a
screenshot can reach the results screen (`=1` still means installations).
`PROTECT_EXPAND=1` opens both disclosures on every finding card — the steps only
exist once somebody clicks, and a screenshot cannot click; the ordering bug above
was only visible with both open. `PROTECT_GEOM` prints the window and
content-view frames.

`mac/Sources/Probe` runs all three scans against the real filesystem and checks
that no key survives `redact()` into an export. Both sets of code-scan false
positives above were caught by running it and reading every line — not by
reasoning about the regular expressions.

    cd mac && swift build --product Probe && .build/debug/Probe ~/Projects/<repo>

⚠️ **The window's owner name is "Templeton Protect", not "Protect".** A screenshot
helper matching on the executable name finds nothing and reports "no window".

Screenshot the window without taking over the screen: get the window id from
`CGWindowListCopyWindowInfo` (no permission prompt) and `screencapture -l<id> -o -x`.
⚠️ Do **not** use `osascript`/System Events for this — it blocks on an
accessibility prompt and hangs.

## Installing

⚠️ **Copy and verify first, then swap.** `rm` then `cp` once destroyed the
installed app when the source was mid-rebuild.

    cp -R "mac/dist/Templeton Protect.app" "/Applications/.Protect.new"
    # verify the staged copy, then:
    rm -rf "/Applications/Templeton Protect.app"
    mv "/Applications/.Protect.new" "/Applications/Templeton Protect.app"

⚠️ **A running app keeps its old Dock icon.** Replacing the bundle under a live
process does not repaint its Dock tile, so a changed icon looks like it did not
ship — quit and relaunch before deciding the icon is wrong. Verify the bundle
rather than the Dock:

    iconutil -c iconset "/Applications/Templeton Protect.app/Contents/Resources/Protect.icns" -o /tmp/x.iconset

## The icon

There are two swirl assets and they are cut differently:

- `mac/Resources/swirl.png` (1024px) — the ambient background mark.
- `mac/Resources/swirl-mark.png` (256px, mask floor 130) — the scanning
  animation and the PDF watermark.

⚠️ **The small one needs a softer mask, and that is measured, not taste.** The
icon uses floor 150 because at 694px a hard edge is invisible. The thinnest arc
in the artwork is 9px at 1024, which is 1.12px at 64pt on a 2x screen — with no
anti-aliasing left it broke into dashes. The body blue runs 119–134 luminance
over 99.9% of its area, so 130 zeroes it (mean leak 0.0002) while keeping 48%
more soft edge than 150. It is also pre-resized with Lanczos rather than
resampled at runtime by SwiftUI, and drawn at 92pt.

`mac/make-icon.py` — Champagne body, Midnight Navy swirl, the mark shared with
Radiant and AiOS, at the same proportions (body 0.896, swirl 0.678) so the three sit together
in the Dock.

- ⚠️ **The swirl is lifted, never re-rendered.** Re-drawing it through a
  blur/threshold pass whose radius scales with output size ate the thin inner
  arcs and turned the rings into blobs.
- ⚠️ **Not a navy body.** That is Radiant's icon in a different blue, and side by
  side in the Dock the two are indistinguishable. The mark is deliberately
  shared; the body colour is what separates the family members.
- ⚠️ The mask's low end is 150, not 120. AiOS's own body blue measures ~116
  luminance, so a floor of 120 left the whole crop box at 0.03–0.10 coverage —
  invisible on Radiant's mid blue, a distinct lighter square on Midnight Navy.

## Releasing

`mac/release.sh` — universal build, sign, DMG, notarise, staple, verify.
`build.sh` stays the fast local loop; it makes something that runs on *this* Mac
only.

    ./release.sh              # full: signed, notarised, stapled DMG
    ./release.sh --no-notary  # stop after signing

Identity: `Developer ID Application: Anthony Ricciardi (5VY66S6G3M)`, already in
the login keychain. Notary credentials are in the keychain profile `AC_PASSWORD`;
recreate with:

    xcrun notarytool store-credentials AC_PASSWORD \
      --apple-id <apple-id> --team-id 5VY66S6G3M --password <app-specific-password>

- ⚠️ **Build both architectures.** `swift build` defaults to this machine's, so
  the app was arm64-only — it would not launch at all on an Intel Mac, which is a
  silent failure for the customer rather than a warning for us.
- ⚠️ **`xattr -cr` before signing.** codesign refuses a bundle carrying resource
  forks or Finder info ("detritus not allowed"), and assets pick those up simply
  by being copied around.
- ⚠️ **Staple both the app and the disk image — and the ORDER is the whole
  thing.** The obvious sequence (package → notarize the image → staple both)
  produces an image whose app carries **no ticket at all**, because the copy
  inside was taken before the staple happened; `stapler staple "$APP"` afterwards
  staples the one in `dist/`, not the one a customer drags to Applications. It
  looks fine — Gatekeeper accepts the app off the mounted image, because the
  image's own ticket covers it — and what it costs you is exactly the case that
  ticket was for: the app dragged out and launched where the notary service
  cannot be reached. Correct order: notarize the **app** (as a zip), staple it,
  build the image around the stapled copy, sign it, notarize the **image**, staple
  that. Two submissions; the second is quick because the contents are already
  notarized. Rebuilding the image invalidates any ticket it had, because a ticket
  is tied to the hash of the thing it was issued for.
- ⚠️ **`spctl --assess` on `dist/` proves nothing about the release.** It passed
  on a build whose packaged app had no ticket. The only check that catches this is
  mounting a quarantined copy of the image and running `stapler validate` on the
  app **inside** it; `release.sh` does this on every run now.
- ⚠️ **Test with the quarantine flag set**, or the test proves nothing:

      xattr -w com.apple.quarantine "0083;00000000;Safari;" "Templeton Protect.dmg"

  then mount it and `spctl --assess --type execute`. Anything from a browser
  carries that flag and it is what Gatekeeper actually reacts to.

## Still open

- Where the DMG is actually hosted for download, and whether it auto-updates.
- Tony to rotate the keys the scan found (TG-281).
- Repo public/private and the licence split (TG-282).
