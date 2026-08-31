# Templeton Protect

**Scan your AI, then scan your code.**

AI agent installations are a new attack surface that nothing audits. Your agents
hold API keys, run shell commands, and keep every conversation forever — and a
repository secret-scanner never looks at any of it.

Protect scans the installations first.

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
