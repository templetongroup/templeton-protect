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

## The footer

"A Templeton Technologies Product" and the mark, linking to templetontech.com —
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

## The icon

`mac/make-icon.py` — Dusty Rose body, the white swirl shared with Radiant and
AiOS, at the same proportions (body 0.896, swirl 0.678) so the three sit together
in the Dock.

- ⚠️ **The swirl is lifted, never re-rendered.** Re-drawing it through a
  blur/threshold pass whose radius scales with output size ate the thin inner
  arcs and turned the rings into blobs.
- ⚠️ **Not a navy body.** That is Radiant's icon in a different blue, and side by
  side in the Dock the two are indistinguishable.
- ⚠️ The mask's low end is 150, not 120. AiOS's own body blue measures ~116
  luminance, so a floor of 120 left the whole crop box at 0.03–0.10 coverage —
  invisible on Radiant's mid blue, a distinct lighter square on Midnight Navy.

## Still open

- **Unsigned** (TG-285). Gatekeeper will refuse it on any other Mac. A security
  product cannot ship asking you to override a security warning.
- Tony to rotate the keys the scan found (TG-281).
- Repo public/private and the licence split (TG-282).
