// What a finding is, and the rules that keep one honest.
//
// ⚠️ A SECURITY TOOL THAT CRIES WOLF IS WORSE THAN NO TOOL. One false finding
// costs somebody a day and costs you the account — and unlike most bad output,
// nobody can tell it is wrong by looking. Everything in this file exists to
// make an overstated finding hard to write.

export type Severity = "critical" | "high" | "medium" | "low";

/**
 * ⚠️ THE LAYERS COME FROM templetongroup/ai-structure-audit, NOT FROM HERE.
 * That skill already defines five nested layers — prompt, context, harness,
 * loop, graph — and audits them from the bottom up. Protect proves things about
 * the harness: tools, permissions, credentials, sandboxing. Emitting the same
 * vocabulary means a Protect scan drops into that report instead of being a
 * second document nobody reconciles.
 */
export type Layer = "prompt" | "context" | "harness" | "loop" | "graph";

export interface Finding {
  /** Stable id for the rule, so a finding can be tracked across runs. */
  rule: string;
  layer: Layer;
  severity: Severity;
  /** What is wrong, in one line, for somebody who is not a security engineer. */
  title: string;
  /** Where. A path, a config key — something the reader can go and look at. */
  where: string;
  /**
   * ⚠️ WHAT WAS ACTUALLY OBSERVED, NOT WHAT IT IMPLIES. "file 644, directory
   * 755" is evidence. "credentials are exposed" is a conclusion, and belongs in
   * the title where it can be argued with.
   */
  evidence: string;
  /** What to do about it. A finding without a fix is just bad news. */
  remedy: string;
  /** How to confirm the fix worked — the skill's report asks for this, rightly. */
  validation: string;
  /**
   * The same finding said to somebody who does not work in security.
   *
   * ⚠️ NOT A SIMPLIFIED VERSION OF THE TITLE — a different sentence, about
   * consequences. "file 644" tells a person nothing; "anyone else who uses this
   * Mac, and any program running under another account, can open this file and
   * read the keys in it" tells them whether to care.
   */
  plain: string;
  /**
   * What the app can do about it, or null when only a person can.
   *
   * ⚠️ NULL IS AN HONEST AND COMMON ANSWER. Nothing here can rotate an API key
   * at the vendor, and a button that pretends otherwise is worse than no button.
   */
  fix: FixAction | null;
}

export interface FixAction {
  /** What the button says. A verb and its object, never "Fix". */
  label: string;
  /** What will happen, in full, before anybody presses it. */
  describes: string;
  kind: "chmod" | "delete-file";
  target: string;
  /** chmod only. */
  mode?: number;
  /**
   * ⚠️ IRREVERSIBLE ACTIONS SAY SO, AND THE UI TREATS THEM DIFFERENTLY. Removing
   * a transcript cannot be undone, and a person deserves to know that before the
   * click rather than after.
   */
  destructive: boolean;
  /**
   * ⚠️ TRUE ONLY WHEN A DETERMINISTIC CHECK PROVED IT. A rule that infers from a
   * pattern — a filename that looks like a secrets file, a key-shaped string
   * that might be a placeholder — sets this false, and the report says so.
   */
  verified: boolean;
}

export const SEVERITY_ORDER: Severity[] = ["critical", "high", "medium", "low"];

export function bySeverity(a: Finding, b: Finding): number {
  const d = SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity);
  // ⚠️ VERIFIED FINDINGS FIRST WITHIN A SEVERITY. What a machine proved outranks
  // what a pattern suggested, always — that ordering is the promise of the tool.
  if (d !== 0) return d;
  if (a.verified !== b.verified) return a.verified ? -1 : 1;
  return a.where.localeCompare(b.where);
}

/**
 * Redact anything that looks like a credential.
 *
 * ⚠️ A SCANNER THAT PRINTS THE SECRET IT FOUND HAS COPIED IT SOMEWHERE NEW —
 * into a terminal, a CI log, a screenshot, a support ticket. The report says
 * where the key is and how many, never what it is.
 */
export function redact(text: string): string {
  return String(text ?? "").replace(
    /\b(sk-[A-Za-z0-9_-]{12,}|aa_[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{20,}|glpat-[A-Za-z0-9_-]{16,})/g,
    (m) => `${m.slice(0, 6)}…[redacted ${m.length} chars]`,
  );
}
