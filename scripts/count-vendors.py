#!/usr/bin/env python3
"""Distinct credential vendor NAMES the engine recognises.

⚠️ NAMES, NOT REGEX TUPLES. keyShapesForRedaction repeats several vendors with
narrower patterns, so counting tuples double-counts — that is exactly how the
landing page came to claim 16 when the real figure was 12.
"""
import glob
import re
import sys
from pathlib import Path

names = set()
for path in glob.glob(sys.argv[1] + "/*.swift"):
    text = Path(path).read_text()
    names |= {
        m.group(1)
        for m in re.finditer(r'\(\s*"([A-Za-z][A-Za-z0-9 ]*)"\s*,\s*try!\s*NSRegularExpression', text)
    }
print(len(names))
