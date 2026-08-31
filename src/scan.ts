import { readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { bySeverity, type Finding } from "./finding.ts";
import { findKeys, transcriptFinding } from "./rules/transcripts.ts";
import {
  looksSensitive,
  reachabilityFinding,
  readPathMode,
  reachableByOthers,
} from "./rules/reachability.ts";

// Walking an AI installation, read-only.
//
// ⚠️ READ-ONLY IS THE CONTRACT, NOT A DEFAULT. templetongroup/ai-structure-audit
// opens with it — "begin read-only… do not change code, configuration, data,
// permissions, or production resources during the audit" — and a scanner that
// touches anything has stopped being an audit. Nothing here opens a file for
// writing, and the CLI has no flag that would.

/** Where the agents keep their configuration and their history. */
export const AI_HOMES = [
  { tool: "Claude Code", dir: ".claude" },
  { tool: "Codex", dir: ".codex" },
  { tool: "OpenClaw", dir: ".openclaw" },
  { tool: "Hermes", dir: ".hermes" },
  { tool: "Cursor", dir: ".cursor" },
  { tool: "Aider", dir: ".aider" },
];

/** Files that hold credentials or decide what an agent may do. */
const CONFIG_NAMES = /^(\.credentials\.json|auth\.json|settings(\.local)?\.json|config\.(json|yaml|yml|toml)|openclaw\.json|\.env(\..*)?)$/;

/** Conversation history — the place nobody thinks to look. */
const TRANSCRIPT_EXT = /\.(jsonl|md|log)$/;
const MAX_READ = 24 * 1024 * 1024;

function walk(root: string, depth = 0, out: string[] = []): string[] {
  if (depth > 6) return out;
  let entries: string[];
  try {
    entries = readdirSync(root);
  } catch {
    return out;
  }
  for (const name of entries) {
    const p = join(root, name);
    let s;
    try {
      s = statSync(p);
    } catch {
      continue;
    }
    if (s.isDirectory()) {
      // node_modules in an agent directory is somebody else's code, not config.
      if (name === "node_modules" || name === ".git") continue;
      walk(p, depth + 1, out);
    } else if (s.isFile()) {
      out.push(p);
    }
  }
  return out;
}

export interface ScanResult {
  findings: Finding[];
  toolsFound: string[];
  filesRead: number;
}

export function scanAiInstallations(home = homedir()): ScanResult {
  const findings: Finding[] = [];
  const toolsFound: string[] = [];
  let filesRead = 0;

  for (const { tool, dir } of AI_HOMES) {
    const root = join(home, dir);
    try {
      if (!statSync(root).isDirectory()) continue;
    } catch {
      continue;
    }
    toolsFound.push(tool);

    for (const path of walk(root)) {
      const name = path.slice(path.lastIndexOf("/") + 1);
      const display = path.replace(home, "~");
      const isConfig = CONFIG_NAMES.test(name);
      const isTranscript = TRANSCRIPT_EXT.test(name);
      if (!isConfig && !isTranscript) continue;

      let size = 0;
      try {
        size = statSync(path).size;
      } catch {
        continue;
      }
      // ⚠️ A CAP, BECAUSE HISTORY GETS BIG. 8 GB of Codex sessions is normal and
      // reading it whole would make the scan unusable — the thing people then
      // stop running.
      if (size > MAX_READ) continue;

      let text = "";
      try {
        text = readFileSync(path, "utf8");
        filesRead += 1;
      } catch {
        continue;
      }

      const mode = readPathMode(path, home);
      const reachable = mode ? reachableByOthers(mode) : false;

      if (isTranscript) {
        const hits = findKeys(text);
        if (hits.length > 0) findings.push(transcriptFinding(display, hits, reachable));
        continue;
      }

      if (reachable) {
        findings.push(reachabilityFinding(mode!, looksSensitive(text), display));
      }
    }
  }

  return { findings: findings.sort(bySeverity), toolsFound, filesRead };
}
