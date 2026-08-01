from __future__ import annotations

import base64
import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from build_ra2_runtime_bundle import encode_png_rgba  # noqa: E402
from validate_ra2_runtime_bundle import (  # noqa: E402
    ValidationError,
    validate_resource_manifest,
    validate_runtime_manifest,
)


def write_b64(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(base64.b64encode(payload).decode("ascii"), encoding="ascii")


class ValidatorTests(unittest.TestCase):
    def test_complete_synthetic_bundle_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            terrain_png = encode_png_rgba(1, 1, bytes([1, 2, 3, 255]))
            cell_payload = struct.pack("<HHBBB", 1, 2, 3, 4, 5)
            resource_payload = struct.pack("<HHHBB", 1, 2, 105, 6, 1)
            write_b64(root / "data/ra2_maps/test_cells_00.b64", cell_payload)
            write_b64(root / "data/ra2_maps/test_terrain_00.b64", terrain_png)
            runtime = {
                "format": "ra2-godot-runtime-v2",
                "render_size": [1, 1],
                "cells": {
                    "chunk_template": "res://data/ra2_maps/test_cells_%02d.b64",
                    "chunk_count": 1,
                    "record_size": 7,
                    "count": 1,
                    "sha256": hashlib.sha256(cell_payload).hexdigest(),
                },
                "background": {
                    "chunk_template": "res://data/ra2_maps/test_terrain_%02d.b64",
                    "chunk_count": 1,
                    "format": "png",
                    "sha256": hashlib.sha256(terrain_png).hexdigest(),
                },
                "resources": {
                    "encoded": base64.b64encode(resource_payload).decode("ascii"),
                    "record_size": 8,
                    "count": 1,
                },
            }
            runtime_path = root / "data/ra2_maps/test_runtime.json"
            runtime_path.parent.mkdir(parents=True, exist_ok=True)
            runtime_path.write_text(json.dumps(runtime), encoding="utf-8")
            result = validate_runtime_manifest(root, runtime_path)
            self.assertEqual(result["cells"], 1)

            atlas_png = encode_png_rgba(4, 1, bytes([1, 1, 1, 255] * 4))
            write_b64(root / "data/ra2_embedded/test_atlas_00.b64", atlas_png)
            assets = {
                asset_id: {"region": [index, 0, 1, 1]}
                for index, asset_id in enumerate(
                    ["tib_01_00", "tib_20_11", "tibtre01_00", "tibtre01_10"]
                )
            }
            resource_manifest = {
                "format": "ra2-resource-atlas-v2",
                "image_format": "png",
                "chunk_template": "res://data/ra2_embedded/test_atlas_%02d.b64",
                "chunk_count": 1,
                "size": [4, 1],
                "sha256": hashlib.sha256(atlas_png).hexdigest(),
                "assets": assets,
                "palette_rules": {
                    "TIB*.TEM": "temperat.pal",
                    "GEM*.TEM": "temperat.pal",
                    "TIBTRE*.TEM": "unittem.pal",
                },
            }
            resource_path = root / "data/ra2_embedded/test_atlas.json"
            resource_path.parent.mkdir(parents=True, exist_ok=True)
            resource_path.write_text(
                json.dumps(resource_manifest), encoding="utf-8"
            )
            resource_result = validate_resource_manifest(root, resource_path)
            self.assertEqual(resource_result["assets"], 4)

    def test_missing_chunk_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "runtime.json"
            path.write_text(
                json.dumps(
                    {
                        "format": "ra2-godot-runtime-v2",
                        "render_size": [1, 1],
                        "cells": {
                            "chunk_template": "res://missing_%02d.b64",
                            "chunk_count": 1,
                            "record_size": 7,
                            "count": 1,
                        },
                        "background": {},
                        "resources": {},
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ValidationError):
                validate_runtime_manifest(root, path)


if __name__ == "__main__":
    unittest.main()
