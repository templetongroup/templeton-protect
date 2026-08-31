import { statSync } from "node:fs";
import { dirname } from "node:path";

import type { Finding } from "../finding.ts";

// Can anybody else on this machine read your agent's credentials?
//
// ⚠️ THE FILE MODE ALONE IS NOT THE ANSWER, AND ASSUMING IT IS PRODUCES EXACTLY
// THE FALSE POSITIVE THAT KILLS A SECURITY TOOL. Written after doing it: a
// scan of Tony's Mac on 2026-08-27 reported ~/.openclaw/openclaw.json as
// world-readable because it is mode 644 — but its directory is 700, so no other
// account can traverse to it. The finding was wrong, and it was stated twice
// before anybody checked the directory.
//
// A file is reachable by another local account only when the file grants read
// AND every directory above it grants execute. This checks the chain.

export interface PathMode {
  path: string;
  fileMode: number;
  /** Modes of each directory from the file up to the home directory. */
  parents: number[];
}

/**
 * Reachable by "others" — a different local account, or a process running as
 * one. Group is folded in with other deliberately: on a single-user Mac the
 * distinction is academic, and the conservative reading is the useful one.
 */
export function reachableByOthers(mode: PathMode): boolean {
  const fileReadable = (mode.fileMode & 0o044) !== 0;
  if (!fileReadable) return false;
  // ⚠️ EVERY directory in the chain must be traversable, not just the closest.
  // A 700 anywhere above it seals the file however open the file itself is.
  return mode.parents.every((m) => (m & 0o011) !== 0);
}

export function octal(mode: number): string {
  return (mode & 0o777).toString(8).padStart(3, "0");
}

/** Walk a real path into the shape the pure check above wants. */
export function readPathMode(path: string, stopAt: string): PathMode | null {
  try {
    const fileMode = statSync(path).mode;
    const parents: number[] = [];
    let dir = dirname(path);
    for (let i = 0; i < 12; i++) {
      parents.push(statSync(dir).mode);
      if (dir === stopAt || dir === "/" || dirname(dir) === dir) break;
      dir = dirname(dir);
    }
    return { path, fileMode, parents };
  } catch {
    return null;
  }
}

/** Does this file hold anything that looks like a credential? */
export function looksSensitive(contents: string): boolean {
  return /\b(sk-[A-Za-z0-9_-]{12,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-|AIza[A-Za-z0-9_-]{20,}|glpat-)/.test(contents)
    || /"(access_?token|refresh_?token|api_?key|client_?secret|password|secret)"\s*:/i.test(contents);
}

/**
 * ⚠️ SEVERITY DEPENDS ON WHAT IS IN THE FILE, NOT ITS NAME. A readable file of
 * permission settings is worth knowing about; a readable file of live tokens is
 * an incident. Calling both "critical" is how a report stops being read.
 */
export function severityFor(sensitive: boolean): Finding["severity"] {
  return sensitive ? "critical" : "low";
}

export function reachabilityFinding(
  mode: PathMode,
  sensitive: boolean,
  display: string,
): Finding {
  return {
    rule: "credential-reachability",
    layer: "harness",
    severity: severityFor(sensitive),
    title: sensitive
      ? "Another account on this Mac can read this file, and it holds credentials"
      : "Another account on this Mac can read this file",
    where: display,
    evidence: `file ${octal(mode.fileMode)}, directories ${mode.parents.map(octal).join(" → ")}`,
    remedy: `chmod 600 "${display}"${sensitive ? " — then rotate anything it contained" : ""}`,
    validation: `stat -f '%Lp' "${display}" returns 600`,
    plain: sensitive
      ? "Anyone else who uses this Mac — and any program running under another account — can open this file and read the keys inside it. Those keys let them act as you with whatever service issued them."
      : "Anyone else who uses this Mac can open this file. It holds no passwords, but it does list what your AI assistant is allowed to do without asking, which is useful to somebody trying to misuse it.",
    fix: {
      label: "Make it private",
      describes: `Sets ${display} so only your account can read it (chmod 600). Nothing is deleted and the file keeps working.`,
      kind: "chmod",
      target: display,
      mode: 0o600,
      destructive: false,
    },
    // Proved by stat on the whole chain, not inferred from the filename.
    verified: true,
  };
}
