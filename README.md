# Templeton Protect

**Scan your Mac, your assistants, and your code.**

AI agents are a new attack surface that nothing audits. They hold API keys, run
shell commands, keep every conversation forever, and are granted standing
permissions nobody revisits — and a repository secret-scanner never looks at any
of it. Meanwhile the Mac they run on is left awake, unlocked and sharing, because
that is what it took to let an agent finish a long job.

Templeton Protect runs three scans and collects the findings into one list.

| Scan | What it looks at |
|---|---|
| **Your hardware** | FileVault, SIP, Gatekeeper, the firewall, what the Mac is sharing, what is listening to the network, whether it sleeps or locks. |
| **Your installations** | Every AI assistant here — conversation logs and configuration for leaked keys and files other accounts can read, **and what the agents are allowed to do**: MCP servers, permission allowlists, hooks, approval policies. |
| **Your code** | A folder you choose — keys committed to source, `.env` files git is not ignoring, database connection strings, private keys, and the code shapes that turn a mistake into a breach. Optionally the repository's whole history. |

Read-only until you ask it to fix something. Every finding is anchored to
something deterministic — a byte pattern, a file mode, an answer from git — never
to a model's guess. Nothing it shows you carries the secret it found.

## Two things you get, and how they are licensed

**The engine is open source (MIT).** Everything that finds and explains a problem
— every rule in `mac/Sources/ProtectCore`, the CLI, the exports. Clone it, read
it, run it, build on it. Cloning this repository and running `swift build` gives
you the complete free scanner, with all three scans and nothing stubbed out.

**The resident layer is a subscription (Protect+).** The part that runs *on your
behalf*: a menu bar presence, scans re-run on a schedule that reports what
changed since last week, and a watcher that flags a key the moment one is written
to a conversation log — instead of whenever you next press the button.

Its source is not in this repository — it ships compiled, inside the signed app.
Nothing is withheld from the free scanner to force an upgrade. The paid thing is
a genuinely different thing: it keeps watch, so you do not have to remember to.

## The command line

The same engine, for a pre-commit hook or a CI job:

```
swift build -c release --product protect-cli
.build/release/protect-cli                     # scan this Mac
.build/release/protect-cli code [path]         # scan a folder
.build/release/protect-cli code --deep [path]  # also walk git history
.build/release/protect-cli code --json --fail-on high [path]   # for CI
```

It exits non-zero when something at or above the threshold is found, so it can
gate a commit. `scripts/install-hook.sh` drops it in as a pre-commit hook.

## Building the app

```
mac/build.sh          # a local build that runs on this Mac
mac/release.sh        # signed, notarized, stapled DMG
```

## Tests

```
npm test              # the TypeScript suite (installations rules)
cd mac && swift test  # the Swift suite — every rule, 60+ tests
```

The Swift suite is where the rules live and where they are pinned. Every false
positive that ever cost a session is a fixture in it.

## License

Engine: MIT (`LICENSE`). The resident application layer is a commercial product;
see `docs/PRODUCT.md` for the split and the reasoning behind it.
