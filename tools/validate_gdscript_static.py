from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def strip_strings_and_comments(source: str) -> str:
    out: list[str] = []
    i = 0
    quote = ""
    while i < len(source):
        ch = source[i]
        if quote:
            if ch == "\\":
                out.extend("  ")
                i += 2
                continue
            if source.startswith(quote, i):
                out.extend(" " * len(quote))
                i += len(quote)
                quote = ""
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue
        if source.startswith('"""', i) or source.startswith("'''", i):
            quote = source[i:i + 3]
            out.extend("   ")
            i += 3
            continue
        if ch in {'"', "'"}:
            quote = ch
            out.append(" ")
            i += 1
            continue
        if ch == "#":
            while i < len(source) and source[i] != "\n":
                out.append(" ")
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def validate_file(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    clean = strip_strings_and_comments(source)
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for index, ch in enumerate(clean):
        if ch in "([{":
            stack.append((ch, index))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                fail(f"{path.relative_to(ROOT)} has unmatched {ch}")
                break
            stack.pop()
    if stack:
        fail(f"{path.relative_to(ROOT)} has unclosed {stack[-1][0]}")

    for line_no, line in enumerate(source.splitlines(), start=1):
        if re.search(r"\bfor\s+.+\s+in\s+.+\s+as\s+(Array|Dictionary)\s*:", line):
            fail(f"{path.relative_to(ROOT)}:{line_no} casts directly in a for expression")


def main() -> int:
    for path in sorted(ROOT.rglob("*.gd")):
        validate_file(path)

    strict_files = [
        ROOT / "scripts/ra2/ra2_database.gd",
        ROOT / "scripts/ra2/ra2_audio_library.gd",
        ROOT / "scripts/ra2/ra2_audio_service.gd",
        ROOT / "scripts/ui/ra2_database_browser.gd",
    ]
    for path in strict_files:
        source = path.read_text(encoding="utf-8")
        if ":=" in source:
            fail(f"{path.relative_to(ROOT)} uses inferred declarations in the new compatibility layer")
        for line_no, line in enumerate(source.splitlines(), start=1):
            if line.lstrip().startswith("func ") and "->" not in line:
                fail(f"{path.relative_to(ROOT)}:{line_no} function lacks an explicit return type")

    if ERRORS:
        print("GDScript static validation failed:")
        for item in ERRORS:
            print(" -", item)
        return 1
    files = list(ROOT.rglob("*.gd"))
    print(f"GDScript static validation passed: {len(files)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
