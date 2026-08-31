#!/usr/bin/env python3
"""Lift the Templeton Protect part of a mixed Claude Code session into this project.

Protect was built inside an AiOS conversation, so that transcript holds both:
roughly 18,800 lines of AiOS work — Mentions, the PDF pipeline, the benchmarks
page — and then everything about this app. Copying the whole file into the
Protect project would file all of that AiOS history under the wrong project;
copying none of it loses how the app got built.

    python3 tools/extract-session.py <source.jsonl> [--from "text that starts it"]

Defaults to the conversation that built the app, cut at the turn where the
security-coworker thread begins.

⚠️ THE SOURCE KEEPS GROWING WHILE THE SESSION IS OPEN. Re-run this at the end of
a session to pick up the tail; it overwrites its output rather than appending.
"""
import argparse, json, os, sys, uuid

DEFAULT_MARK = "can we levereage this into aios"
PROJECT = os.path.expanduser("~/.claude/projects/-Users-tonyricciardi-Projects-templeton-protect")


def user_text(d):
    c = d.get("message", {}).get("content")
    if isinstance(c, list):
        return " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return c if isinstance(c, str) else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--from", dest="mark", default=DEFAULT_MARK)
    ap.add_argument("--out-dir", default=PROJECT)
    ap.add_argument("--session-id", default=None)
    args = ap.parse_args()

    lines = []
    start = None
    with open(args.source, errors="ignore") as f:
        for i, line in enumerate(f):
            lines.append(line)
            if start is not None:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") == "user" and args.mark.lower() in user_text(d).lower():
                start = i

    if start is None:
        sys.exit(f"never found a user turn containing {args.mark!r} — nothing written")

    sid = args.session_id or str(uuid.uuid5(uuid.NAMESPACE_URL, args.source + "|" + args.mark))
    os.makedirs(args.out_dir, exist_ok=True)
    out = os.path.join(args.out_dir, sid + ".jsonl")

    kept = 0
    with open(out, "w") as w:
        first = True
        for line in lines[start:]:
            try:
                d = json.loads(line)
            except Exception:
                continue
            # ⚠️ REPAIR THE CHAIN AT THE CUT. Every entry names its parent, and the
            # first one kept points at a turn that is no longer in the file — an
            # orphan reference that makes the transcript look truncated rather
            # than deliberately started here.
            if first and "parentUuid" in d:
                d["parentUuid"] = None
                first = False
            d["sessionId"] = sid
            w.write(json.dumps(d) + "\n")
            kept += 1

    print(f"  cut at line {start + 1} of {len(lines):,}")
    print(f"  kept {kept:,} entries → {out}")
    print(f"  {os.path.getsize(out) / 1e6:.1f} MB (source was {os.path.getsize(args.source) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
