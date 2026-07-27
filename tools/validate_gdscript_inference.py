#!/usr/bin/env python3
"""Reject custom function calls assigned with := when the function has no return type.

This is not a replacement for running Godot headless. It catches the exact class of
regression that broke v0.10.0's RA2 database browser.
"""
from __future__ import annotations
import re
from collections import defaultdict
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\([^)]*\)\s*(.*?)\s*:\s*$")
INFER_CALL_RE = re.compile(r":=\s*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)\s*\(")

untyped: dict[str, list[str]] = defaultdict(list)
for path in SCRIPTS.rglob("*.gd"):
    for number, line in enumerate(path.read_text("utf-8").splitlines(), 1):
        match = FUNC_RE.match(line)
        if match and "->" not in match.group(2):
            untyped[match.group(1)].append(f"{path.relative_to(ROOT)}:{number}")

failures: list[str] = []
for path in SCRIPTS.rglob("*.gd"):
    for number, line in enumerate(path.read_text("utf-8").splitlines(), 1):
        if ":=" not in line:
            continue
        match = INFER_CALL_RE.search(line)
        if match and match.group(1) in untyped:
            failures.append(
                f"{path.relative_to(ROOT)}:{number}: {line.strip()} -> "
                f"custom function '{match.group(1)}' has no return type: "
                f"{', '.join(untyped[match.group(1)])}"
            )

if failures:
    print("GDScript inference regression(s) found:", file=sys.stderr)
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print("GDScript inference check passed.")
