# Templeton Protect

**Scan your Mac, your assistants, and your code.**

AI agent installations are a new attack surface that nothing audits. Your agents
hold API keys, run shell commands, and keep every conversation forever — and a
repository secret-scanner never looks at any of it. Meanwhile the machine they
run on is left awake, unlocked and sharing, because that is what it took to let
an agent finish a long job.

The Mac app runs three scans and collects the findings into one list:

| Scan | What it looks at |
|---|---|
| **Your hardware** | FileVault, SIP, Gatekeeper, the firewall, what the Mac is sharing, what is listening to the network, whether it sleeps or locks. |
| **Your installations** | Every AI assistant installed here — conversation logs and configuration, for keys left behind and files other accounts can read. |
| **Your code** | A folder you choose — keys committed to the repository, `.env` files git is not ignoring, and the code shapes that turn a mistake into a breach. |

⚠️ **The CLI below is the installations scan only.** The hardware and code scans
are in the Swift engine that the Mac app runs; the TypeScript engine has not
caught up. See `HANDOFF.md`.

```bash
node --experimental-strip-types src/cli.ts            # human-readable
node --experimental-strip-types src/cli.ts --markdown # report format
```

Read-only. Nothing here opens a file for writing, and there is no flag that
would. The report never prints a credential it finds.

## What it checks today

**Credentials in agent transcripts.** Keys get pasted into conversations, echoed
out of `.env` files, printed by a command the agent ran. Nobody thinks of a chat
log as a credential store, so nobody scans one. Scanning a single developer Mac
found 64 key-shaped values across 13 transcript files, in 9.2 GB of history that
nothing rotates.

**Credential reachability.** Whether another account on the machine can actually
read a config file — checking the file mode *and* every directory above it. A
644 file inside a 700 directory is not exposed, and a scanner that says it is
will not be trusted twice.

## What it found that nobody had published

Codex writes its session transcripts mode `644`. Claude Code writes its
transcripts mode `600`. Same secrets, different exposure.

## Design rules

- **Every finding is verified, or says it isn't.** A rule that infers from a
  pattern marks itself, and the report sorts proven findings above inferred ones.
- **Severity follows the contents, not the filename.** A readable settings file
  is worth knowing about; a readable file of live tokens is an incident.
- **Never print the secret.** Reporting a key by value copies it into a terminal,
  a CI log, a screenshot, a support ticket.
- **One finding per thing to fix.** A transcript with forty keys is one action.

## Where it fits

Findings use the layer vocabulary from
[templetongroup/ai-structure-audit](https://github.com/templetongroup/ai-structure-audit),
which audits AI systems across prompt, context, harness, loop and graph. Protect
proves things about the **harness**; that skill reasons about the rest. A Protect
run drops into its report rather than being a second document nobody reconciles.

## License

MIT.
