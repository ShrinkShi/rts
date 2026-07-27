from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import zipfile


def prepare_source(value: str | Path, cache_root: str | Path, pack_name: str) -> Path:
    source = Path(value).expanduser().resolve()
    if source.is_dir():
        return source
    if not source.is_file() or source.suffix.casefold() != ".zip":
        raise FileNotFoundError(f"{pack_name} source must be an extracted directory or ZIP file: {source}")
    digest = hashlib.sha1(source.read_bytes()).hexdigest()[:12]
    target = Path(cache_root).resolve() / f"{pack_name}-{digest}"
    marker = target / ".complete"
    if marker.exists():
        return target
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as archive:
        archive.extractall(target)
    marker.write_text(source.name, encoding="utf-8")
    return target
