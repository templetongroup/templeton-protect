import test from "node:test";
import assert from "node:assert/strict";

import { reachableByOthers, severityFor, octal } from "../src/rules/reachability.ts";
import { findKeys, redactKeys, transcriptFinding } from "../src/rules/transcripts.ts";
import { redact, bySeverity } from "../src/finding.ts";

// ⚠️ A SECURITY TOOL THAT CRIES WOLF IS WORSE THAN NO TOOL, and one that stays
// quiet is worse still. Both directions are pinned here.

test("a file is only reachable when the whole directory chain allows it", () => {
  // ⚠️ THE MISTAKE THIS PREVENTS, MADE FOR REAL on 2026-08-27:
  // ~/.openclaw/openclaw.json was reported world-readable because it is 644.
  // Its directory is 700, so no other account can traverse to it. Wrong, and
  // stated twice before anybody checked the directory.
  assert.equal(reachableByOthers({ path: "x", fileMode: 0o644, parents: [0o755, 0o755] }), true);
  assert.equal(reachableByOthers({ path: "x", fileMode: 0o644, parents: [0o700, 0o755] }), false);
  // A 700 anywhere ABOVE it seals the file too, not just the closest directory.
  assert.equal(reachableByOthers({ path: "x", fileMode: 0o644, parents: [0o755, 0o700] }), false);
  // An owner-only file is safe whatever the directories say.
  assert.equal(reachableByOthers({ path: "x", fileMode: 0o600, parents: [0o777, 0o777] }), false);
});

test("severity follows what is in the file, not its name", () => {
  // A readable file of settings is worth knowing; a readable file of live
  // tokens is an incident. Calling both critical is how a report stops working.
  assert.equal(severityFor(true), "critical");
  assert.equal(severityFor(false), "low");
});

test("real keys are found", () => {
  assert.equal(findKeys("sk-proj-9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u").length, 1);
  assert.equal(findKeys("ghp_9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6uQ2xZ").length, 1);
  assert.equal(findKeys("AIzaSyD9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u").length, 1);
});

test("documentation placeholders are not findings", () => {
  // A rule that flags the example key in a README teaches people to ignore it.
  assert.equal(findKeys("sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx").length, 0);
  assert.equal(findKeys("sk-YOUR-API-KEY-HERE-REPLACE-THIS-NOW").length, 0);
  assert.equal(findKeys("use sk-EXAMPLE-KEY-PLACEHOLDER-VALUE-X").length, 0);
});

test("a key that merely starts with letters is still a key", () => {
  // ⚠️ THE FALSE NEGATIVE THIS PREVENTS: the first placeholder filter matched a
  // prefix list containing "abcd", which silently ate a real key beginning
  // "abcdef…". For a scanner, a missed finding is the worse half of the trade.
  assert.equal(findKeys("sk-abcdefghijklmnopqrstuvwxyz012345").length, 1);
});

test("exposure raises severity, storage alone does not", () => {
  const hits = [{ vendor: "OpenAI", length: 40 }];
  assert.equal(transcriptFinding("~/a.jsonl", hits, true).severity, "critical");
  assert.equal(transcriptFinding("~/a.jsonl", hits, false).severity, "high");
});

test("one finding per file, however many keys are in it", () => {
  // Forty rows for one file would bury every other finding in the report.
  const many = Array.from({ length: 40 }, () => ({ vendor: "OpenAI", length: 40 }));
  const f = transcriptFinding("~/a.jsonl", many, false);
  assert.match(f.evidence, /40 key-shaped/);
});

test("the report never prints the secret it found", () => {
  // ⚠️ A scanner that echoes a key has copied it somewhere new — a terminal, a
  // CI log, a screenshot, a support ticket.
  const out = redact("found sk-proj-9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u in the log");
  assert.equal(out.includes("9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u"), false);
  assert.match(out, /redacted/);
});

test("verified findings outrank inferred ones at the same severity", () => {
  const base = { rule: "r", layer: "harness", severity: "high", title: "t", where: "w", evidence: "e", remedy: "m", validation: "v" };
  const sorted = [{ ...base, verified: false }, { ...base, verified: true }].sort(bySeverity);
  assert.equal(sorted[0].verified, true);
});

test("octal formatting is readable", () => {
  assert.equal(octal(0o644), "644");
  assert.equal(octal(0o600), "600");
});


// ⚠️ THE FIX MUST NOT BE WORSE THAN THE PROBLEM. This rule used to offer only
// "delete this transcript" — destroying somebody's whole conversation to remove
// one key, on a machine that may not be ours. Tony: "that would be incredibly
// destructive." Redaction has to take the key out and leave everything else.
test("redacting a transcript removes the keys and keeps the conversation", () => {
  const before = [
    'here is the key sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345 use it',
    'and a token ghp_AbCdEfGh1jKlMn0pQrStUvWxYz01234567',
    'a placeholder like sk-YOUR-KEY-HERE should be left alone',
    'ordinary conversation worth keeping',
  ].join("\n");

  const { text, removed } = redactKeys(before);

  assert.equal(removed, 2, "both real keys should be removed");
  assert.equal(findKeys(text).length, 0, "no key-shaped values may remain");
  assert.ok(text.includes("sk-YOUR-KEY-HERE"), "a placeholder is not a key and must survive");
  assert.ok(text.includes("ordinary conversation worth keeping"), "the conversation must survive");
  assert.equal(text.split("\n").length, before.split("\n").length, "no lines may be lost");
  assert.ok(!text.includes("Ab3dEfGh1jKlMn0pQrStUvWxYz012345"), "the secret itself must be gone");
});

test("redacting a transcript with no keys changes nothing", () => {
  const clean = "just a normal conversation\nwith two lines";
  const { text, removed } = redactKeys(clean);
  assert.equal(removed, 0);
  assert.equal(text, clean, "a file with nothing to fix must come back byte for byte");
});

test("the offered fix is redaction, and it is not destructive", () => {
  const f = transcriptFinding("~/a.jsonl", findKeys("sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345"), false);
  assert.equal(f.fix.kind, "redact-in-file");
  assert.equal(f.fix.destructive, false);
});
