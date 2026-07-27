#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from ra2_pipeline.builder import BuildPaths, DatabaseBuilder
    from ra2_pipeline.source import prepare_source
else:
    from .builder import BuildPaths, DatabaseBuilder
    from .source import prepare_source


def parse_extra(raw: str) -> tuple[str, str]:
    if "=" not in raw:
        raise argparse.ArgumentTypeError("--extra must use NAME=PATH")
    name, value = raw.split("=", 1)
    return name.strip(), value


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the complete RA2/YR database, previews, localization, audio and maps")
    parser.add_argument("--ra2", required=True, help="ra2.zip or extracted RA2 directory")
    parser.add_argument("--ra2md", required=True, help="ra2md.zip or extracted YR directory")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--extra", action="append", default=[], type=parse_extra, help="higher-priority official/patch archive as NAME=PATH")
    parser.add_argument("--ra2-csf", type=Path)
    parser.add_argument("--ra2md-csf", type=Path)
    parser.add_argument("--audio", help="RA2 audio.zip or extracted directory containing audio.idx/audio.bag and WAV files")
    parser.add_argument("--audio-md", help="YR audiomd.zip or extracted directory containing audio.idx/audio.bag and WAV files")
    arguments = parser.parse_args()

    project = arguments.project.resolve()
    cache = project / ".ra2_cache" / "source"
    ra2_root = prepare_source(arguments.ra2, cache, "ra2")
    ra2md_root = prepare_source(arguments.ra2md, cache, "ra2md")
    extra_roots: list[tuple[str, Path]] = []
    for name, source in arguments.extra:
        extra_roots.append((name, prepare_source(source, cache, name)))
    output = project / "data" / "ra2"

    builder = DatabaseBuilder(BuildPaths(ra2_root, ra2md_root, output, tuple(extra_roots)))
    builder.load()
    database = builder.build()
    builder.write(database)

    preview_script = Path(__file__).with_name("preview.py")
    preview_command = [
        sys.executable,
        str(preview_script),
        "--ra2-root", str(ra2_root),
        "--ra2md-root", str(ra2md_root),
        "--database", str(output / "database.json"),
        "--output", str(project / "assets" / "ra2_preview"),
    ]
    for name, root in extra_roots:
        preview_command.extend(("--extra", f"{name}={root}"))
    subprocess.run(preview_command, check=True)

    supplemental_requested = any(value is not None for value in (arguments.ra2_csf, arguments.ra2md_csf, arguments.audio, arguments.audio_md))
    if supplemental_requested:
        if arguments.ra2_csf is None or arguments.ra2md_csf is None or arguments.audio is None:
            parser.error("--ra2-csf, --ra2md-csf and --audio must be supplied together")
        audio_root = prepare_source(arguments.audio, cache, "audio")
        audio_md_root = prepare_source(arguments.audio_md, cache, "audiomd") if arguments.audio_md is not None else None
        supplemental_script = Path(__file__).with_name("build_supplemental.py")
        supplemental_command = [
            sys.executable,
            str(supplemental_script),
            "--project", str(project),
            "--ra2-csf", str(arguments.ra2_csf.resolve()),
            "--ra2md-csf", str(arguments.ra2md_csf.resolve()),
            "--audio-root", str(audio_root),
        ]
        if audio_md_root is not None:
            supplemental_command.extend(("--audio-md-root", str(audio_md_root)))
        for name, root in extra_roots:
            supplemental_command.extend(("--extra", f"{name}={root}"))
        subprocess.run(supplemental_command, check=True)

    validation_script = Path(__file__).with_name("validate.py")
    subprocess.run([sys.executable, str(validation_script), "--project", str(project)], check=True)
    subprocess.run([sys.executable, str(project / "tools" / "validate_gdscript_static.py")], check=True)

    print("RA2/YR pipeline completed and validated.")
    print(f"Database: {output / 'database.json'}")
    print(f"Preview: {project / 'assets' / 'ra2_preview' / 'RA2_PIPELINE_PREVIEW.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
