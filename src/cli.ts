#!/usr/bin/env node --experimental-strip-types
import { homedir } from "node:os";

import { redact, SEVERITY_ORDER, type Finding } from "./finding.ts";
import { scanAiInstallations } from "./scan.ts";

// Scan your AI, then scan your code.
//
// ⚠️ THE REPORT IS THE PRODUCT. Findings nobody reads are the same as no
// findings, so the output leads with what to do and says plainly which lines a
// machine proved. Shape follows templetongroup/ai-structure-audit's report
// template, so a Protect run drops into that audit instead of being a second
// document nobody reconciles.

const BADGE: Record<Finding["severity"], string> = {
  critical: "CRITICAL",
  high: "HIGH    ",
  medium: "MEDIUM  ",
  low: "LOW     ",
};

function main(): void {
  const markdown = process.argv.includes("--markdown");
  const home = homedir();
  const started = Date.now();
  const { findings, toolsFound, filesRead } = scanAiInstallations(home);
  const seconds = ((Date.now() - started) / 1000).toFixed(1);

  if (markdown) {
    console.log("# Templeton Protect — AI installation scan\n");
    console.log(`Scanned ${toolsFound.length} installation(s): ${toolsFound.join(", ")}.`);
    console.log(`Read ${filesRead} configuration and transcript files in ${seconds}s.\n`);
    if (findings.length === 0) {
      console.log("No findings. Nothing here is reachable by another account and no credentials are sitting in history.\n");
      return;
    }
    console.log("## Findings\n");
    for (const f of findings) {
      console.log(`### [${f.severity.toUpperCase()}] ${f.title}\n`);
      console.log(`- Layer: ${f.layer}`);
      console.log(`- Where: \`${f.where}\``);
      console.log(`- Evidence: ${redact(f.evidence)}`);
      console.log(`- Confidence: ${f.verified ? "verified by direct check" : "pattern match, not confirmed"}`);
      console.log(`- Recommended fix: ${f.remedy}`);
      console.log(`- Validation: ${f.validation}\n`);
    }
    return;
  }

  console.log(`\n  Templeton Protect — scanning ${toolsFound.length} AI installation(s)`);
  console.log(`  ${toolsFound.join(", ")}`);
  console.log(`  ${filesRead} files read in ${seconds}s\n`);

  if (findings.length === 0) {
    console.log("  Nothing found. No credentials in history, nothing readable by another account.\n");
    return;
  }

  for (const severity of SEVERITY_ORDER) {
    const group = findings.filter((f) => f.severity === severity);
    if (group.length === 0) continue;
    for (const f of group) {
      console.log(`  ${BADGE[severity]}  ${f.title}`);
      console.log(`            ${f.where}`);
      console.log(`            ${redact(f.evidence)}`);
      console.log(`            fix: ${f.remedy}`);
      // ⚠️ SAY WHEN A FINDING WAS ONLY INFERRED. The reader decides how much to
      // trust it, and hiding the difference is how a tool loses their trust once.
      if (!f.verified) console.log(`            (pattern match — not confirmed)`);
      console.log("");
    }
  }

  const counts = SEVERITY_ORDER.map((s) => `${findings.filter((f) => f.severity === s).length} ${s}`).join(", ");
  console.log(`  ${findings.length} finding(s): ${counts}\n`);
}

main();
