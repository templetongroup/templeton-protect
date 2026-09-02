# Selling Protect+

## There is no server, and there does not need to be one yet

A Protect+ licence is a signed expiry date. The app checks the signature against
a public key inside its own bundle and compares the date to the clock. It never
calls home — not at activation, not on a schedule, not at all.

That has one large consequence worth saying plainly: **selling this needs a
store, not a backend.** Paddle and Lemon Squeezy both deliver a licence key from
a list you upload. You mint the list; they take the money, handle VAT as merchant
of record, and email the key. Nothing of ours has to be online, and — the part
that matters — the signing key never leaves the login keychain to sit on a web
server where a compromise would mean minting rights.

## Minting a batch

    swift scripts/licence-tool.swift batch 25 365 2026-09

Writes `licences-2026-09.csv` in the working directory: one key per line, with
the batch id and the expiry date. Upload it as the store's key list.

The file is gitignored, and it should stay out of every repo, backup folder and
chat window. Every line in it is a working subscription that anybody can redeem.

⚠️ **The clock starts at minting, not at purchase.** The expiry is an absolute
date baked into the key. Mint 300 keys today with a one-year term and the one
sold next August is worth a month. Mint small batches, monthly, and top the store
up — the tool takes two seconds.

## Issuing one by hand

For a refund, a support case, a reviewer, a friend:

    swift scripts/licence-tool.swift issue someone@example.com 365
    swift scripts/licence-tool.swift verify TP1-...

`issue` puts the real email in the key. Nothing enforces it — the app reads only
the expiry — but it makes a key traceable if it turns up somewhere public.

## What renewal costs us

A renewed subscription needs a **new key**, because the old one's date cannot
move. Month one, that is a person emailing and getting one back. It does not stay
that way, and there are two ways out:

1. **Automate the current design.** A webhook on the store's renewal event mints
   a key and emails it. Straightforward, and it means the signing key lives on a
   server. That is the trade: convenience against a secret that can no longer
   only exist on one Mac.
2. **Make the term start at activation.** The key would carry a duration rather
   than a date, and the app would stamp the start on first use. Batches would stop
   ageing on the shelf and renewal would still need a new key, but nothing would
   need to be online. It needs a new key version and an app that understands it.

Neither is built. (2) is the better shape and should be decided before the store
opens, because it changes what a sold key looks like. See TG-300.

## Before the first sale

- [ ] Store account exists (Paddle or Lemon Squeezy — merchant of record, so VAT
      and sales tax are theirs to handle, not ours).
- [ ] Decide absolute-expiry vs term-from-activation. This changes the keys.
- [ ] Point `Store.checkout` at the hosted checkout instead of the product page.
- [ ] Upload the first batch, buy one with a real card, and redeem the key in a
      clean install. Not a test-mode order — the whole path, once, for real.
