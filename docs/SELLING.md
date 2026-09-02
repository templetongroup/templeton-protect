# Selling Protect+

## The store is Paddle, and it is set up

Live catalog, created 2026-09-02:

| What | ID |
|---|---|
| Product — Templeton Protect+ | `pro_01m1hsp5k7e7bp5mc9gh6wpk5r` |
| $5/month | `pri_01m1hsq8qhs61npwszh9awp4fm` |
| $50/year | `pri_01m1hsr0m7p4pp5j5gzc2da5r8` |

Checkout is Paddle.js on the landing page, using the public client-side token
`live_6ef5b17f00bb6204ce343347aa7`. `templetongroup.dev` is submitted for domain
approval and pending.

⚠️ **PADDLE DOES NOT HAND OUT LICENCE KEYS.** Lemon Squeezy sells from a list of
keys you upload; Paddle Billing has no equivalent. So `batch` is not the
fulfilment path here — with Paddle a key is delivered either by a webhook we
write, or by hand. At the volumes this starts at, by hand is correct: the store
emails you the order, `issue` takes two seconds.

⚠️ **NOTHING CAN BE SOLD UNTIL BUSINESS VERIFICATION PASSES**, which needs
personal identity details and bank details and is Tony's to complete. Checkout
will not open before then, on any domain.

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

**The clock starts when the customer enters the key, not when you mint it.** A
batch can sit in the store without losing value, so mint as much inventory as you
like.

⚠️ **Every key still dies two years past its term, whatever its activation date.**
That is not an oversight to be tidied up later — it is the only thing stopping a
leaked key from being a free subscription forever. The activation date is stamped
on the customer's own Mac and anybody determined enough can clear it; the void
date is inside the signed key and cannot be moved.

## Issuing one by hand

For a refund, a support case, a reviewer, a friend:

    swift scripts/licence-tool.swift issue someone@example.com 365
    swift scripts/licence-tool.swift verify TP1-...

`issue` puts the real email in the key. Nothing enforces it — the app reads only
the expiry — but it makes a key traceable if it turns up somewhere public.

## What renewal costs us

A renewed subscription needs a **new key**, because a key's term is fixed once it
is signed. Month one, that is a person emailing and getting one back — the store
tells you who renewed, `issue` takes two seconds.

Automating it means a webhook on the store's renewal event minting and emailing a
key, and that puts the signing key on a web server. It is the one thing here
worth being slow about: a compromised server would mean minting rights over every
future subscription, and the private key currently exists on exactly one Mac.
Worth doing when the volume justifies it, not before.

## The two key shapes

**TP2** is what `issue` and `batch` mint: a term in days plus a void date. The
term starts on first use.

**TP1** was an absolute end date, and the app still reads it, permanently. Keys
already in somebody's hands cannot be recalled, so this is not a migration — it
is a second shape that has to keep working. See TG-300.

## The one switch to flip

When Paddle verification passes **and** `templetongroup.dev` shows Approved under
Checkout &rarr; Request domain approval, set `PADDLE_READY = true` in the checkout
script at the bottom of `showcase/protect/index.html` and publish.

⚠️ **Do not flip it early to test.** With either one outstanding,
`Paddle.Checkout.open()` still returns normally and paints Paddle's own
"Something went wrong &mdash; contact support" panel over the page, unbranded. It
does not throw, so no `try`/`catch` around the call can turn that back into our
own message. That is why the gate is a flag before the call rather than error
handling around it.

## Before the first sale

- [ ] Store account exists (Paddle or Lemon Squeezy — merchant of record, so VAT
      and sales tax are theirs to handle, not ours).
- [ ] Ship an app that understands TP2 **before** minting anything for sale.
      Version 0.8.0 or later. A TP2 key entered into an older copy is refused.
- [ ] Point `Store.checkout` at the hosted checkout instead of the product page.
- [ ] Upload the first batch, buy one with a real card, and redeem the key in a
      clean install. Not a test-mode order — the whole path, once, for real.
