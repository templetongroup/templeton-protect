import { chmodSync, lstatSync, rmSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

import { AI_HOMES } from "./scan.ts";
import type { FixAction } from "./finding.ts";

// Applying a fix, which is the only place this program writes anything.
//
// ⚠️ EVERY GUARD BELOW ASSUMES THE REQUEST IS HOSTILE, because one day it will
// be. The UI is a local web page; a page in another tab can post to a localhost
// server. So a fix is not "do what the request says" — it is "prove the target
// is one of ours, prove it is still what we found, then act".

export interface FixOutcome {
  ok: boolean;
  message: string;
}

function expand(target: string): string {
  return resolve(target.startsWith("~") ? join(homedir(), target.slice(1)) : target);
}

/**
 * ⚠️ THE TARGET MUST LIVE INSIDE AN AI INSTALLATION WE SCAN. Without this a
 * crafted request could chmod or delete anything the user can — the whole home
 * directory included. Path is resolved first, so "~/.claude/../../etc/passwd"
 * fails here rather than succeeding quietly.
 */
export function insideScannedTree(target: string, home = homedir()): boolean {
  const full = expand(target);
  return AI_HOMES.some(({ dir }) => {
    const root = resolve(join(home, dir));
    return full === root || full.startsWith(root + "/");
  });
}

export function applyFix(fix: FixAction, home = homedir()): FixOutcome {
  const full = expand(fix.target);

  if (!insideScannedTree(fix.target, home)) {
    return { ok: false, message: "That path is outside the folders this app scans, so it will not be touched." };
  }

  // ⚠️ lstat, NOT stat. A symlink pointing somewhere sensitive would otherwise
  // let a chmod or a delete land on the target instead of the link.
  let info;
  try {
    info = lstatSync(full);
  } catch {
    return { ok: false, message: "That file is already gone. Re-scan to refresh the list." };
  }
  if (info.isSymbolicLink()) {
    return { ok: false, message: "That path is a symbolic link, so it is left alone." };
  }
  if (!info.isFile()) {
    return { ok: false, message: "That path is not a regular file, so it is left alone." };
  }

  if (fix.kind === "chmod") {
    const mode = fix.mode ?? 0o600;
    try {
      chmodSync(full, mode);
    } catch (err) {
      return { ok: false, message: `Could not change permissions: ${err instanceof Error ? err.message : "unknown"}` };
    }
    // ⚠️ CONFIRM IT ACTUALLY TOOK. Reporting success without checking is how a
    // tool tells somebody they are safe when they are not.
    const now = statSync(full).mode & 0o777;
    return now === mode
      ? { ok: true, message: `Now readable only by you (${now.toString(8)}).` }
      : { ok: false, message: `Permissions did not change — still ${now.toString(8)}.` };
  }

  if (fix.kind === "delete-file") {
    try {
      rmSync(full);
    } catch (err) {
      return { ok: false, message: `Could not delete it: ${err instanceof Error ? err.message : "unknown"}` };
    }
    return { ok: true, message: "Deleted. The keys that were in it still need rotating at the service that issued them." };
  }

  return { ok: false, message: "That is not a fix this app knows how to apply." };
}
