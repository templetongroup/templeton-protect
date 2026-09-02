# Templeton Protect — working notes

Read this before changing the Mac app. Every line is something that already went
wrong and cost real time.

## The resident layer (Protect+)

`mac/Sources/Protect/Resident.swift` — menu bar, schedule, transcript watcher —
plus `Watcher.swift` and `History.swift` in core so they can be tested, and
`Plan.swift` for the free/paid gate.

- ⚠️ **FSEvents needs `kFSEventStreamCreateFlagUseCFTypes`.** Without it the
  callback's `paths` argument is a C `char**`; casting it to `CFArray` is a
  segfault, not an error. The watcher test died on signal 11 until the flag went
  in — which is the entire argument for the watcher living in core where a test
  can reach it. It would have shipped.
- ⚠️ **Schedule on an hourly due-date check, not a 7-day timer.** A laptop that
  sleeps through a long timer never fires it; the hourly check runs the scan on
  the first wake past due, which is what "weekly" means to a machine that closes
  at night.
- ⚠️ **HistoryStore compares THEN saves.** Reversed, it diffs a scan against
  itself and reports eternal "no change" — which reads as safety and is a bug.
  Records are written 600 under Application Support (700); a security tool whose
  own memory is world-readable is its own first finding.
- ⚠️ **Closing the window must not quit when watch is on.**
  `applicationShouldTerminateAfterLastWindowClosed` returns `!resident.enabled`.
  The app lives in the menu bar; Quit is the menu item.
- ⚠️ **`NSApp.windows.first` IS NOT YOUR WINDOW once a status item exists.**
  The menu bar's "Open Templeton Protect" did
  `NSApp.windows.first?.makeKeyAndOrderFront(nil)` and did nothing at all —
  `NSApp.windows` also holds the status bar's own window and `.first` is not
  documented to be the one you meant, so the call raised a 22pt strip in the
  menu bar. Measured rather than guessed: after clicking the item the frontmost
  application was Preview. The delegate owns its window and exposes
  `showWindow()`; the Resident holds a closure, never a search.
- ⚠️ **`activate` is a request, so follow it with `orderFrontRegardless()`.**
  Recent macOS may refuse a background app's activation, and a refused activate
  leaves the window behind whatever is in front of it — a button that silently
  does nothing, which this project has a rule against.
- ⚠️ **A NOTIFICATION NEEDS A DELEGATE OR THE TAP GOES NOWHERE.** Tony: "the
  notfications that pop up go nowhere when you click them." Without
  `UNUserNotificationCenter.current().delegate`, a tap is simply dropped — and an
  alert whose entire content is "go and look at this" has to be the thing that
  takes you there. Set the delegate at launch, before asking for authorization:
  a tap is delivered to whoever is the delegate at that moment, so setting it
  when the first notification is posted loses every tap on one already sitting in
  Notification Center. Also implement `willPresent`, or macOS suppresses the
  banner whenever the app is frontmost.
- ⚠️ **ONE LEAKED KEY IS ONE ALERT, ACROSS RESTARTS.** The reported-paths set
  lived in memory, so every relaunch re-announced every transcript that still
  held a key. After a morning of test builds Tony had a stack of them: "im also
  getting constant pings like this now." A resident tool that cries the same wolf
  on every launch is one people mute, and a muted alert is worse than none
  because it looks like cover. What is remembered is a **fingerprint** — which
  vendors, how many — persisted in UserDefaults and keyed by a **hash of the
  path**, because preferences are world-readable and this app's own bookkeeping
  must not become the list of where somebody's secrets live. An appended-to
  session holding the same key stays silent; a genuinely new key still speaks.
  A burst of files coalesces into one banner.
- ⚠️ **NAME THE ASSISTANT, NOT THE FILE.** Claude Code names sessions by UUID, so
  the alert read "keys in 1a183aae-5627-487d-b514-c49ed7c7c117.jsonl" — a fact
  nobody can act on. `TranscriptWatcher.agent(forPath:)` maps the path back to
  "a Claude Code conversation"; the exact path is on the finding card.
- ⚠️ **NOTIFICATIONS CANNOT BE TESTED ON A LOCAL BUILD.** macOS ties notification
  authorization to the app's code signature, and `build.sh` signs ad-hoc — a
  fresh signature every build, so the system sees a different app and denies it.
  Two runs of identical code minutes apart logged `didGrant: 1` and then
  `didGrant: 0` for exactly this reason, which looked like a flaky bug and was
  the loop measuring itself. Test notification behavior only on the signed,
  notarized build. Read the truth with:

      log show --predicate 'process == "Protect"' --last 60s --style compact \
        | grep -iE "Requested authorization|Added notification"

  `didGrant: 0 hasError: 1` arriving a millisecond after the request is a refused
  signature, not a user who said no.
- ⚠️ **THE FOOTER MARK IS THE CANARY FOR WINDOW HEIGHT.** It is the last thing
  on the opening screen, so if it is not visible on launch the window is too
  short. This has regressed twice: at 720 when the page grew, and again at 860
  the moment the Keep watch row went in — Tony: "the main window does not show
  the templeton technologies logo when it opens." Now 1000. **Screenshot the
  window after adding anything to the idle screen**; do not assume the old
  number still holds.
- ⚠️ **A ROW THAT NEVER WRAPS BREAKS WORDS.** The scanning stage tiles were an
  HStack, so six stages divided the width into ~110pt each and SwiftUI split
  words mid-word — "OpenCla / w", "Agent permissi / ons". Tony: "this formatting
  is awful. text is jumbled." Use a `LazyVGrid` with a minimum column width so
  it wraps to a second row, and give the label `lineLimit` +
  `minimumScaleFactor` so it truncates rather than hyphenates.
- ⚠️ **`isReleasedWhenClosed` is true by default for a programmatic NSWindow.**
  The delegate holds its own strong reference, so the red button handed the
  window to AppKit to destroy while `window` still pointed at it. With keep-watch
  on, closing the window is a normal thing to do and reopening it is the entire
  point of the menu item. Set it false.
- ⚠️ **`Plan.current` defaults to `.plus` and that is deliberate.** There is no
  store, so gating features behind an impossible purchase is theater. The gate
  makes the boundary visible; flipping the default to `.free` is the launch
  decision, with the payment rails, and it is Tony's not an agent's.

## Licensing

`License.swift` verifies, `scripts/licence-tool.swift` issues.

- ⚠️ **THE OLD CHECK WAS `count >= 8`.** Anyone could type `aaaaaaaa` and hold
  Protect+ for good — and the repository is public, so the code saying so was
  there to read. A key is now `TP1-<payload>.<signature>`, Ed25519 over the
  payload, verified against `TPLicenceKey` in Info.plist. The email and expiry
  come OUT of the signed payload; nothing the customer types is trusted.
- ⚠️ **The stored licence file is re-verified, not trusted.** It sits in
  Application Support where anyone can edit it. Without re-checking the
  signature on every entitlement query, forging Protect+ would be editing JSON
  rather than typing a fake key — easier than the hole it replaced.
- ⚠️ **The private key is in the login keychain and nowhere else**, under
  `ai.templetongroup.protect.licence-signing`, and it is a SEPARATE key from
  Sparkle's. One compromise should not cost both the ability to sell and the
  ability to ship — and a stolen update key is the worse of the two, because it
  ships code. `licence-tool.swift generate` refuses to overwrite an existing
  key: every licence ever issued would stop verifying.
- ⚠️ **The trial stamp is written twice and the earliest wins.** It lived only
  in UserDefaults, so `defaults delete ai.templetongroup.protect firstRunDate`
  bought another fourteen days. A second copy sits beside the licence file and
  each read restores the other.
- ⚠️ **None of this stops a recompile, and no client-side scheme can.** Signing
  raises the floor — invented keys, keygens, one key on a forum. It does not
  build a ceiling. Anyone weighing more enforcement should read the note in
  docs/PRODUCT.md first: the only unbreakable model puts the value on a server,
  and this product's whole claim is that nothing leaves the Mac.

## Claims on the landing page

`scripts/verify-claims.sh` recomputes every number on the page from the engine
and fails if one has drifted. `release.sh` runs it before it builds.

- ⚠️ **It exists because one was wrong.** The page shipped a draft claiming 16
  credential vendors when the figure is 12 — the regex tuples had been counted,
  and `keyShapesForRedaction` repeats several. A false number on a security
  scanner's own marketing page is precisely what the product exists to catch.
  The discipline is borrowed from T3MP3ST's `verify-claims`.
- ⚠️ **Match stats by a KEYWORD in the label, never the whole label.** The page
  is designed by another hand and the wording moves — "rules" became
  "fact-anchored rules" between one run and the next. Exact matching reports
  MISSING on every rewrite, which teaches people to ignore the script.
- The egress claim is checked as an *absence*: no HTTP client anywhere in
  `ProtectCore`. Sparkle lives in the app target, and the page says so.

## The agent-permissions audit

`mac/Sources/ProtectCore/Agents.swift`, run as a stage of the installations scan.

- ⚠️ **Evidence names the env variable, never its value.** An MCP config env
  block is exactly where a live credential sits; quoting it copies the key onto
  the screen. `looksLikeLiveCredential` decides by name-shape plus the same
  placeholder test the finder uses, so `${VAR}` passthroughs and "changeme" stay
  quiet.
- ⚠️ **The permission allowlist rule is tight on purpose.** `Bash(git status)`
  is somebody's quieter afternoon and none of our business. Only the unfenced
  shell (`Bash(*)`) and dangerous wildcards (sudo/rm/curl with a `*`) are flagged.
- ⚠️ **Blast radius fires only on the combination.** An agent reading what the
  account reads is how computers work, not a finding. The finding is an unfenced
  grant AND `~/.ssh`/`~/.aws` on disk — then one sentence says the reach out loud.

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
- The scanner reading **its own documentation**, three times: `NOTES.md`
  explaining that a bundle contains `eval(str)`, `Code.swift`'s comment saying
  the same, and a paragraph about PEM handling reported as a **critical**
  credential leak at the top of the report. Whack-a-mole was not the fix. Each
  pattern rule now declares the languages it means anything in — Markdown does
  not execute and Swift has no `eval` — and keys are still read out of every
  file type, because a key pasted into a README is a leaked key.
- A PEM header on its own, matched in prose. The rule now requires forty
  characters of base64 after it, which is what separates a key from a sentence
  about keys. It also left the vendor list: sitting there, its name was
  substituted into a title built for issuers and produced "a private key file
  credential written into the code". A key with no issuer needs its own sentence.
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
- ⚠️ **The watermark uses `swirl.png` (1024px), NOT `swirl-mark.png` (256px).**
  Tony: *"the swirl at the bottom is pixelated."* It is drawn at 460pt, which on
  paper at 300dpi is about 1,900 device pixels — the small asset was being
  stretched more than sevenfold. A PDF is resolution-independent and the raster
  inside it is not, so the source has to be large enough for the size it is
  *printed* at, not the size it looks on screen. The two swirls are cut
  differently on purpose (see The icon); the large one is right here and the
  small one is right for the scanning animation.
- ⚠️ **`Probe` has to load the mark from disk.** It is not a bundle, so the
  export's default `Bundle.main.image(forResource:)` returns nil and the PDF
  comes out with no watermark at all — which is how a first attempt to inspect
  this found nothing wrong with it. `PROTECT_EXPORT_DIR=/tmp` writes all three
  formats out.
- ⚠️ **The print palette is the screen palette darkened.** Champagne is invisible
  on paper and dusty rose is too light to read at 9pt. The darkened set is
  declared once at the top of `ExportPDF.swift` rather than reached for ad hoc.
- ⚠️ **The watermark is clipped-and-filled, not drawn.** The mark asset is white
  ink on transparency — right for the screen, and on white paper it produces
  exactly nothing, which is what the first version shipped. Use it as a mask and
  fill navy.

## Updating, and selling

`Updater.swift` (Sparkle), `License.swift` + `Plan.swift` (the trial and the gate),
`LicenceSheet.swift` (entering a key). The appcast lives at
`templetongroup.dev/showcase/protect/appcast.xml`; `release.sh` generates and
signs it and stages the DMG into the site repo.

- ⚠️ **THE UPDATE CHECK IS THE ONLY THING THIS APP SENDS, EVER.** Before Sparkle
  there was no network client in the binary at all. `SUEnableSystemProfiling` is
  explicitly false and `SUEnableAutomaticChecks` is deliberately ABSENT, so
  Sparkle asks before it automates rather than deciding for somebody. If that
  ever grows a second endpoint, the privacy page has to grow with it.
- ⚠️ **SIGN SPARKLE INSIDE-OUT.** The framework carries two XPC services, an
  Autoupdate helper and an Updater.app; signing the outer bundle does not reach
  them, and unsigned nested code is a notary rejection. `--deep` is Apple's own
  "do not use this" flag — name each piece.
- ⚠️ **The rpath is in `Package.swift`.** The app is hand-assembled so nothing
  sets one; without `@executable_path/../Frameworks` the binary builds cleanly
  and dies at launch with "image not found".
- ⚠️ **Protect's DMG rides git; Radiant's does not.** Ours is ~3 MB against
  Radiant's ~163 MB, so `.gitignore` in the site repo carries an exception for
  `showcase/protect/*.dmg`. That exception is what makes publishing a push
  instead of an FTP upload — and Sparkle's appcast points at that exact file.
- ⚠️ **`.htaccess` must serve `.xml` as XML.** Served as anything else, every
  installed copy silently stops finding updates. And the site has an SPA
  fallback, so a missing file returns **200 with the homepage** — verify a
  deploy by `Content-Type` and byte length, never by status.
- ⚠️ **SwiftPM COMPILES `.metal` FILES BY ITSELF, and that breaks the universal
  build.** Even with no `resources:` declaration it picks them up, and a
  `--arch arm64 --arch x86_64` build then needs the full Metal Toolchain, which
  is a separate Xcode download: `swift build` dies with "cannot execute tool
  'metal'". `exclude: ["Shaders"]` in `Package.swift`, and `build.sh` /
  `release.sh` compile them with `xcrun metal` instead — which works without the
  extra component. One metallib serves both architectures; it holds AIR, which
  is GPU-family specific rather than CPU specific.

  ⚠️ This failure reads exactly like a notarisation problem, because the release
  script prints "▸ building universal" and then stops. Check the top of the log
  before blaming Apple — twice now that diagnosis has been wrong.
- ⚠️ **`ShaderLibrary` NEEDS A COMPILED `default.metallib`, NOT THE SOURCE.**
  Declaring a `.metal` file as a SwiftPM resource copies the *source* into the
  bundle; `ShaderLibrary.default` then finds nothing and every effect silently
  does nothing, which looks like a design choice rather than a bug.
- ⚠️ **`colorEffect` GIVES THE SHADER A POSITION BUT NOT A SIZE.** Pass the real
  size from a `GeometryReader`; a placeholder divides by zero and renders a flat
  rectangle that looks like the shader failed to load.
- ⚠️ **A BACKGROUNDED `release.sh` DIES WITH THE TOOL CALL THAT POLLS IT.**
  `nohup … &` survives SIGHUP, not the SIGTERM a timed-out foreground command
  takes its process group down with. The 0.5.0 release was killed mid-flight
  between stapling the image and writing the appcast, leaving a valid DMG and a
  stale feed. Run long releases as a tracked background task, and check the
  appcast actually regenerated before publishing.
- ⚠️ **Notarising the DMG can outrun a ten-minute command timeout.** `release.sh`
  in the foreground was killed mid-flight, leaving a stapled app and an
  unstapled disk image. Run it backgrounded, or finish with `notarytool submit`
  + `stapler staple` on the DMG alone.
- ⚠️ **A LAPSED SUBSCRIPTION MUST LOOK LAPSED.** The keep-watch switch read from
  the stored preference, so a lapsed copy showed the toggle ON beside the words
  "Keeping watch is off". It reads from the entitlement now. For this product
  that is not a cosmetic bug: a control that looks like cover and is not is the
  exact failure the whole thing exists to prevent.
- The trial is 14 days, and an unreachable store gets a 14-day grace period —
  cutting a paying customer off because our server was down on a Tuesday is
  punishing them for our outage. Lapsing never disables scanning.

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

## The paid layer lives in another repo

- The private repo is `templetongroup/templeton-protect-plus`. `scripts/link-plus.sh`
  symlinks it into `mac/Sources/{ProtectCore,Protect}/Plus/`; `--off` unlinks it,
  which is how you check the free build still stands alone. Both folders are
  gitignored, so the private sources cannot land in the public repo by accident.
- ⚠️ **`swift build` picks free-or-paid while the MANIFEST is evaluated**, from
  `hasPlus()` in `mac/Package.swift`, and **SwiftPM caches manifests by content**.
  `touch Package.swift` does not clear it. Adding or removing the Plus folders
  without deleting `mac/.build/manifest.db`, `mac/.build/manifests` and
  `~/.swiftpm/cache/manifests` leaves the previous answer in force, and the build
  fails with ordinary-looking `cannot find 'Resident' in scope` — so you go
  hunting through the `#if PROTECT_PLUS` guards, which are fine. It cost an hour
  in each direction: a "free build" that was really the cached paid one, and a
  paid build that failed as though a guard were wrong. `link-plus.sh` clears all
  three now; if you touch the Plus folders by hand, clear them yourself.
- ⚠️ **The licensing tests used to run against the installed app.** `Licensing`
  writes its licence and first-run stamp to `~/Library/Application Support/
  Templeton Protect/`, and the tests had no override, so `swift test` read and
  rewrote the real ones. It passed on the day of an install and then failed
  forever after with `trial(daysLeft: 13)` vs `14` — the suite was measuring how
  long Protect had actually been on this Mac. `Licensing.storageOverride` now
  points every test at a throwaway directory. A test that rebuilds that path by
  hand defeats it; use `Licensing.licenceLocation`.
- `forget()` deliberately leaves the first-run stamp. Giving up a licence must
  not hand back a fresh trial.

## Fixes, confirmation, and what `destructive` means

- ⚠️ **`destructive` means "ask before doing it", not "harms the file".** The
  redaction fix — the gentle one, that takes the key out and leaves the
  conversation byte for byte — was flagged `destructive: false` in both rule
  sets, and both test suites pinned it there. The flag is what routes a fix
  through the confirmation step, so one click permanently rewrote somebody's
  transcript with no copy and nothing in the Trash. It is `true` now, in Swift
  and TypeScript, and the tests pin the transcript surviving (the `kind`) rather
  than the flag.
- Nothing else in either rule set sets it true, so before this the whole arm and
  confirm path in `FindingCard` was unreachable code.
- Fixes delete and rewrite outright rather than moving to the Trash, and that is
  deliberate: a file full of leaked keys sitting recoverable in the Trash is not
  a fix. It also means **there is nothing to undo**, so do not add an undo
  affordance — the safety has to live in the press. That is what `HoldToConfirm`
  in `Sources/Protect/Motion.swift` is for, and it falls back to a plain button
  under reduce-motion or VoiceOver.
- ⚠️ **`HOME=… ` does not sandbox a scan.** Running the built app with a fake
  home to try a fix safely does not work — the scan still read the real home and
  reported 7,406 files. To exercise a fix without touching real data, write a
  throwaway transcript inside the real home and remove it afterwards.
- ⚠️ **The results list cannot be driven by System Events.** `entire contents of
  window 1` returns nothing for these SwiftUI views and Page Down does not scroll
  the list, so a card below the fold cannot be reached from a script. Verifying
  anything down there means doing it by hand.

## Licence keys have two shapes

- **TP2** is what gets minted now: a term in days, stamped when the customer
  first enters it, plus a void date. **TP1** was an absolute end date and is
  still read, permanently — keys already sold cannot be recalled, so it is a
  second shape and not a migration.
- ⚠️ **Never remove the void date, and never read a missing one as "no limit".**
  The activation stamp lives on the customer's Mac and can be cleared; the void
  date is inside the signed key and cannot. Without it, one leaked key is a free
  subscription forever for anybody who clears their stamp. A TP2 payload with no
  `n` is refused.
- ⚠️ **A TP2 key entered into 0.7.0 or older is refused**, because those builds
  only parse TP1. Nothing may be minted for sale until an app that understands
  TP2 is the one people download.
- The activation stamp is keyed by a hash of the licence, never the licence.
  Preferences are readable by anybody logged in here, and a working key sitting
  in a plist is a subscription somebody can copy.

## Changing the Dock icon

- `make-icon.py` writes **both** `icon-1024.png` and `Protect.icns` now. Only the
  `.icns` ships — `build.sh` and `release.sh` copy that and never look at the png
  — so regenerating the png alone used to change nothing visible and read as a
  silent failure.
- ⚠️ **Quitting and relaunching is NOT enough**, whatever the older note said,
  and neither is `killall Dock`, nor `lsregister -f`, nor clearing
  `~/Library/Caches/com.apple.iconservices.store`. All four were tried in turn on
  a bundle that was already correct. The caches that actually held the old tile
  live in the per-boot temp folders:

      osascript -e 'quit app "Templeton Protect"'
      find /private/var/folders -name com.apple.dock.iconcache -delete
      find /private/var/folders -maxdepth 5 -name "com.apple.iconservices" -exec rm -rf {} +
      killall iconservicesagent; killall Dock

  Give it ten seconds before judging the result.

- ⚠️ **Verify the bundle, not the Dock.** Before chasing the cache, check what
  actually shipped: `shasum` the app's `Contents/Resources/Protect.icns` against
  `mac/Protect.icns`, or read the body colour out of it. Twice the Dock was wrong
  and the app was right, and treating the Dock as the source of truth sends you
  rebuilding something that was already correct.
- The family is told apart by **body colour**, not the mark: Radiant `#5377B3`,
  AiOS `#857F5E`, Protect `#192A56`. Protect was champagne-bodied until
  2026-09-02. It went to `#0B1329` first, purely for distance from Radiant, and
  that read as a black tile rather than a blue one. `#192A56` is the lightest
  step that still separates by tone at 32px; `#2A4C96` and above start trading
  places with Radiant, which is the failure this is guarding against.

## Still open

- Tony to rotate the keys the scan found (TG-281).
- Sales backend: a webhook that mints and emails a licence on a completed order.
