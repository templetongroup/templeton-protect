# Templeton Protect

*Product shape · 27 Aug 2026*

A security coworker that delivers a finished assessment, sold three ways. This is the shape I'd build, and the two decisions worth making before any code.

## What it is

Point it at something you own — a codebase, a cloud tenancy, a Microsoft 365 estate — and it returns a report a human can act on: what's actually at risk here, ranked, with the remediation drafted and re-checked. Not a wall of scanner output.

The scanners it leans on are free and already excellent. **The product is not the scanning. It's the triage.** Semgrep on a real repository produces hundreds of findings and most are noise; Microsoft's own tooling will tell you about 200 misconfigurations without saying which three matter this week. Judging that is the work, and it's the part a model is genuinely good at.

## Settle this first: who is it for?

Code scanning and posture auditing sound like one product. They are sold to two different people, and only one of them is your client.

OpenWorker ships code security first because Andrew Ng's audience is engineers. Templeton's clients are small businesses — the demo tenant is a plumbing company. They have no codebase. They will never buy a static analysis tool.

They do have a Microsoft 365 tenancy nobody has audited, admin accounts without MFA, a former employee whose access was never revoked, and sharing links to files they think are private. **That is the same product with the scanners swapped, and it sells to the people you already invoice.**

My recommendation is to build posture first and treat code scanning as the later, optional module. It reaches your existing customers, it demonstrates in ten minutes on a real tenancy, and the findings are the kind a business owner understands without translation.

## The licensing decision

You want it open-source on GitHub, sold as a subscription, and bundled into paid AiOS plans. Those three can coexist, but only one arrangement does it honestly — and we watched the other one fail this week.

### MIT the engine. Sell the operation.

Everything that finds and explains a problem is MIT, like Radiant. What people pay for is not permission to run it — it's that it runs on a schedule, keeps history so you can show something improved, tracks findings across clients, and has someone to call.

That's already your model with AiOS, and it's honest: nothing is withheld from the free version to force an upgrade. The paid thing is genuinely a different thing.

### Why not open-core

Stirling-PDF was ruled out for AiOS on 17 August for exactly this. Its root licence is MIT and then carves out `engine/`, which requires a paid per-user subscription for production use — and the README doesn't say so. The evaluation misread it twice in one day.

If Protect's GitHub page says "open source" while the useful half is paid, it earns that same reaction from the next person who reads the licence carefully. Open-core can be done well, but only by stating the split in the first paragraph of the README, and it costs you the goodwill that made you want to open-source it.

### One thing to check before publishing

The scanners have their own licences and they are not uniform. Semgrep's core is LGPL with a commercially-licensed ruleset; Trivy is Apache 2.0; Nessus is proprietary. Bundling a scanner into a product you sell is a different permission from running it yourself. Read each licence for what *you* are doing with it — that's RULES #65, and it has already cost this project two sessions.

## Three channels, one core

Same engine underneath, three thin adapters. This is the split AiOS already uses for PDFs — the browser does what a browser can, the box does what needs a machine — and it works because the core knows nothing about which one is calling it.

## The spine: two rules that make it trustworthy

### Every finding is anchored to something deterministic

A model may rank, explain and draft the fix. It may not be the sole source of a finding. Anything the model raised on its own is labelled as such and sorted below the anchored ones.

This is the difference between a product and a liability. An AI security tool that invents a vulnerability wastes a day of a client's engineering time and is never trusted again — and unlike most bad output, nobody can tell it's wrong by looking.

### The fixer is never the only checker

This is OpenWorker's phrase and it's the right one. A proposed fix is re-scanned and diff-reviewed before it reaches a human. The thing that wrote the patch does not get to be the thing that says the patch is good.

It's the same instinct as AiOS proving a guard bites by breaking what it guards — an assertion nobody tested is just an opinion.

## What AiOS already gives it

- **The approval bridge**, built today. Unattended work that hits something consequential files a request and waits rather than guessing — exactly what a scanner wanting to run against production needs.
- **The audit log**, so every action an agent took is recoverable. Half of what makes a security product buyable is being able to answer "what did it do".
- **Capabilities and plans**, so it can be switched on per client and per tier without new machinery.
- **Local models**, added today. A client's code or configuration never leaving their own hardware is a selling point no hosted competitor can match.
- **The Mac app shell**, if the open-source version ever wants a window rather than a terminal.
## Where it sits in the plans

Full tier, alongside `feat:ocr` — the tier described in `plans.ts` as the one "that has a machine behind it", which is exactly what running scanners requires. Essentials and Professional get the findings that come from configuration a client has already connected; Full gets scheduled scans and history.

It needs its own capability rather than riding an existing one, because a client having Protect is a commercial fact and Mission Control needs a lever for it. That means a `role_permissions` backfill ships with it — RULES #49, which has bitten twice.

## What could go wrong

### A false finding

Told a client they have a critical vulnerability and they don't. Costs them a day, costs you the account. Mitigated by the anchoring rule above, and by never using the word "critical" for anything a model raised alone.

### Credentials

Auditing a client's Microsoft 365 means holding keys to it. That is a materially larger promise than anything AiOS makes today, and it changes your insurance and contract position before it changes your architecture. Worth a conversation with whoever writes your MSA before this ships.

### Scanner licences

Covered above. Cheap to check, expensive to discover late.

### A quiet failure

A scan that silently stops running is worse than no scan, because the client believes they're covered. Every run must report, including the ones that found nothing — the same rule that fixed Signals this week.

## The cheapest way to find out if it's real

Not a platform. One scan, on one thing you already have access to.

- Audit the Templeton Microsoft 365 or Google Workspace tenancy — MFA coverage, admin count, dormant accounts, external sharing, legacy auth.
- Have a model rank the findings and write the report as if for a client who isn't technical.
- Read it yourself and ask: would I send this, and would they pay for it?
That's a few days, it uses your own tenancy so nobody is exposed, and it answers the only question that matters before any of the above is worth building. Note that nothing is installed yet — the box has ClamAV but no Semgrep, Trivy or Gitleaks, so step zero is picking the first scanner and installing it.
