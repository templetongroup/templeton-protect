# Templeton Protect — working notes

Read this before changing the Mac app. Every line is something that already went
wrong and cost real time.

## Where things are

| What | Where |
|---|---|
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
    PROTECT_AUTOSCAN=1 "mac/dist/Templeton Protect.app/Contents/MacOS/Protect"

`PROTECT_AUTOSCAN` runs a real scan on launch so a screenshot can reach the
results screen. `PROTECT_GEOM` prints the window and content-view frames.

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
- ⚠️ **Staple both the app and the disk image.** The ticket on the image lets it
  open offline; the one inside the app survives being dragged out of the image.
- ⚠️ **Test with the quarantine flag set**, or the test proves nothing:

      xattr -w com.apple.quarantine "0083;00000000;Safari;" "Templeton Protect.dmg"

  then mount it and `spctl --assess --type execute`. Anything from a browser
  carries that flag and it is what Gatekeeper actually reacts to.

## Still open

- Where the DMG is actually hosted for download, and whether it auto-updates.
- Tony to rotate the keys the scan found (TG-281).
- Repo public/private and the licence split (TG-282).
