import type { Finding } from "../finding.ts";

// Credentials sitting in agent conversation logs.
//
// ⚠️ THIS IS THE RULE NOBODY ELSE RUNS, AND IT IS THE ONE THAT FINDS THINGS. A
// repo secret-scanner looks at repositories. Nobody points one at
// ~/.claude/projects or ~/.codex/sessions, because a chat log is not thought of
// as a credential store. It is: keys get pasted into conversations, echoed out
// of env files, printed by a command the agent ran. Found on Tony's own Mac
// 2026-08-27 — 64 key-shaped strings across 13 files, 9.2 GB of history with no
// rotation, in directories mode 755.
//
// ⚠️ THE SEVERITY IS THE KEY, NOT THE FILE. A transcript is not sensitive
// because it is a transcript; it is sensitive because of what somebody pasted
// into it. A rule that flags every transcript is noise.

/** Patterns specific enough that a match is worth acting on. */
const KEY_SHAPES: { name: string; re: RegExp }[] = [
  { name: "OpenAI", re: /\bsk-[A-Za-z0-9_-]{20,}\b/g },
  { name: "Anthropic", re: /\bsk-ant-[A-Za-z0-9_-]{20,}\b/g },
  { name: "GitHub", re: /\bgh[pousr]_[A-Za-z0-9]{30,}\b/g },
  { name: "Google", re: /\bAIza[A-Za-z0-9_-]{30,}\b/g },
  { name: "Slack", re: /\bxox[baprs]-[A-Za-z0-9-]{20,}\b/g },
  { name: "GitLab", re: /\bglpat-[A-Za-z0-9_-]{16,}\b/g },
  { name: "Artificial Analysis", re: /\baa_[A-Za-z0-9]{24,}\b/g },
];

/**
 * ⚠️ THE OBVIOUS PLACEHOLDERS ARE EXCLUDED, because a rule that flags the
 * example key in a README teaches people to ignore it. Documentation is full of
 * sk-xxxxx and sk-YOUR-KEY-HERE, and every one of those is a false positive.
 */
/**
 * ⚠️ IT MUST MATCH THE WHOLE BODY, NOT ITS FIRST FEW CHARACTERS. The first
 * version tested a prefix list that included "abcd", which silently ate a real
 * key beginning "abcdef…" — a false NEGATIVE, and for a security scanner a
 * missed finding is the worse half of the trade. A placeholder is a body that is
 * one repeated character, or one that says in words that it is not a key.
 */
function isPlaceholder(body: string): boolean {
  if (/^(.)\1{5,}$/.test(body)) return true;
  return /\b(your|example|placeholder|redacted|sample|dummy|replace|here|xxxx)\b/i.test(body)
    || /^(x{4,}|0{4,}|1{4,})/i.test(body);
}

export interface KeyHit {
  vendor: string;
  /** The value is never kept — only enough to prove it was not a placeholder. */
  length: number;
}

export function findKeys(contents: string): KeyHit[] {
  const hits: KeyHit[] = [];
  for (const { name, re } of KEY_SHAPES) {
    for (const match of contents.matchAll(re)) {
      const value = match[0];
      if (isPlaceholder(value.replace(/^(sk-ant-|sk-|gh[pousr]_|AIza|xox.-|glpat-|aa_)/, ""))) continue;
      hits.push({ vendor: name, length: value.length });
    }
  }
  return hits;
}

/**
 * Replace every key-shaped value with a marker, leaving everything else byte for
 * byte as it was.
 *
 * ⚠️ THE FIX FOR A KEY IS NOT DESTROYING THE CONVERSATION. The only remedy this
 * rule used to offer was deleting the whole transcript — for a scanner aimed at
 * other people's machines that is a cure worse than the disease, so nobody
 * presses it and the key stays. Tony: "if it surfaces something like an openai
 * key in a transcript, how can we delete the entire session from their folders?
 * that would be incredibly destructive."
 *
 * Built from KEY_SHAPES, the same list the scan matches on, so the fix cannot
 * quietly cover less than the finding claims. Placeholders are skipped for the
 * same reason they are not reported.
 */
export function redactKeys(contents: string): { text: string; removed: number } {
  let removed = 0;
  let text = contents;
  for (const { name, re } of KEY_SHAPES) {
    text = text.replace(new RegExp(re.source, re.flags.includes("g") ? re.flags : re.flags + "g"), (m) => {
      if (isPlaceholder(m.replace(/^(sk-ant-|sk-|gh[pousr]_|AIza|xox.-|glpat-|aa_)/, ""))) return m;
      removed++;
      // Same length is not the goal; saying what happened is. A reader of this
      // transcript later should understand why the value is gone.
      return `[${name} key removed by Templeton Protect]`;
    });
  }
  return { text, removed };
}

/**
 * ⚠️ ONE FINDING PER FILE, NOT ONE PER KEY. A transcript with forty matches is
 * one thing to fix — delete or rotate — and forty rows would bury every other
 * finding in the report.
 */
export function transcriptFinding(display: string, hits: KeyHit[], reachable: boolean): Finding {
  const vendors = [...new Set(hits.map((h) => h.vendor))].sort();
  return {
    rule: "secrets-in-transcripts",
    layer: "harness",
    // Reachable by another account turns a stored secret into an exposed one.
    severity: reachable ? "critical" : "high",
    title: `Live credentials are sitting in an agent transcript`,
    where: display,
    evidence: `${hits.length} key-shaped value(s) — ${vendors.join(", ")} — in a conversation log${reachable ? ", in a directory other accounts can read" : ""}`,
    validation: "Re-run the scan; this file should report no key-shaped values.",
    plain: `A conversation with an AI assistant was saved to disk, and ${hits.length === 1 ? "a password-like key was" : hits.length + " password-like keys were"} left sitting in it in plain text${reachable ? " — in a folder other accounts on this Mac can read" : ""}. Keys usually end up here because somebody pasted one into the chat, or a command printed one. These logs are kept forever and nothing clears them out.`,
    remedy: "Rotate those keys, then take the key out of this transcript. Agent history is kept forever by default and nothing rotates it.",
    fix: {
      label: "Remove the key from this transcript",
      describes: `Replaces ${hits.length === 1 ? "the key-shaped value" : `all ${hits.length} key-shaped values`} in ${display} with a marker and leaves the rest of the conversation exactly as it was. It does NOT rotate the keys — only the service that issued them can do that, and you should treat them as compromised either way.`,
      kind: "redact-in-file",
      target: display,
      // Editing one value out of a file is not destroying somebody's history.
      // Deleting the whole transcript to remove a key is a cure worse than the
      // disease, and on a client's machine it is not ours to do.
      destructive: false,
    },
    // Proved by matching a vendor-specific key shape, with placeholders excluded.
    verified: true,
  };
}
