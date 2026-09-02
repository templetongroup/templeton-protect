#!/usr/bin/env python3
"""Read one data-count from the landing page, matched by a keyword in its label.

⚠️ MATCH ON A KEYWORD, NOT THE WHOLE LABEL. The page is designed by another
hand and the wording moves — "rules" became "fact-anchored rules", and the
egress line became "bytes of scan data sent anywhere", between one check and the
next. An exact-label match reports MISSING on every rewrite, which trains people
to ignore this script. A keyword survives copy edits that do not change what is
being claimed, and AMBIGUOUS is reported rather than guessed at when a keyword
starts matching two stats.
"""
import re
import sys
from pathlib import Path

html = Path(sys.argv[1]).read_text()
key = sys.argv[2].lower()
hits = [
    m for m in re.finditer(r'data-count="(\d+)"[^<]*</b>\s*<span>([^<]*)</span>', html)
    if key in m.group(2).lower()
]
print(hits[0].group(1) if len(hits) == 1 else ("AMBIGUOUS" if hits else "MISSING"))
