#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from ra2_pipeline.builder import BuildPaths, DatabaseBuilder
else:
    from .builder import BuildPaths, DatabaseBuilder


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a provenance-preserving RA2/YR database")
    parser.add_argument("--ra2-root", required=True, type=Path)
    parser.add_argument("--ra2md-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--extra", action="append", default=[], help="higher-priority source as NAME=PATH")
    arguments = parser.parse_args()

    extra_roots: list[tuple[str, Path]] = []
    for raw in arguments.extra:
        if "=" not in raw:
            parser.error("--extra must use NAME=PATH")
        name, value = raw.split("=", 1)
        root = Path(value).resolve()
        if not root.is_dir():
            parser.error(f"extra source is not a directory: {root}")
        extra_roots.append((name, root))

    builder = DatabaseBuilder(BuildPaths(arguments.ra2_root, arguments.ra2md_root, arguments.output, tuple(extra_roots)))
    builder.load()
    database = builder.build()
    builder.write(database)
    print(json.dumps(database["summary"], ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
