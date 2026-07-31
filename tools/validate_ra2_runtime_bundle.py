#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import struct
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class ValidationError(ValueError):
    pass


def load_json(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"Invalid JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValidationError(f"JSON root must be an object: {path}")
    return value


def res_path(project_root: Path, value: str) -> Path:
    if not value.startswith("res://"):
        raise ValidationError(f"Expected res:// path, got {value!r}")
    return project_root / value.removeprefix("res://")


def decode_chunks(project_root: Path, template: str, count: int) -> bytes:
    if count <= 0:
        raise ValidationError(f"Chunk count must be positive for {template}")
    encoded = ""
    for index in range(count):
        path = res_path(project_root, template % index)
        if not path.is_file():
            raise ValidationError(f"Missing runtime chunk: {path}")
        encoded += path.read_text(encoding="ascii").strip()
    try:
        return base64.b64decode(encoded, validate=True)
    except ValueError as exc:
        raise ValidationError(f"Invalid Base64 payload for {template}: {exc}") from exc


def verify_hash(payload: bytes, expected: str, label: str) -> None:
    actual = hashlib.sha256(payload).hexdigest()
    if expected and actual != expected:
        raise ValidationError(
            f"{label} SHA-256 mismatch: expected {expected}, got {actual}"
        )


def png_dimensions(payload: bytes) -> tuple[int, int]:
    if not payload.startswith(PNG_SIGNATURE):
        raise ValidationError("Image payload is not PNG")
    if payload[12:16] != b"IHDR":
        raise ValidationError("PNG does not begin with IHDR")
    width, height = struct.unpack_from(">II", payload, 16)
    if width <= 0 or height <= 0:
        raise ValidationError(f"Invalid PNG dimensions: {width}x{height}")
    return width, height


def validate_runtime_manifest(project_root: Path, path: Path) -> dict[str, int]:
    manifest = load_json(path)
    if manifest.get("format") != "ra2-godot-runtime-v2":
        raise ValidationError(
            f"Unsupported runtime manifest format: {manifest.get('format')!r}"
        )

    cells = manifest.get("cells")
    background = manifest.get("background")
    resources = manifest.get("resources")
    if (
        not isinstance(cells, dict)
        or not isinstance(background, dict)
        or not isinstance(resources, dict)
    ):
        raise ValidationError(
            "Runtime manifest must define cells, background and resources objects"
        )

    cell_payload = decode_chunks(
        project_root,
        str(cells.get("chunk_template", "")),
        int(cells.get("chunk_count", 0)),
    )
    record_size = int(cells.get("record_size", 0))
    record_count = int(cells.get("count", 0))
    if record_size != 7:
        raise ValidationError(f"Cell record size must be 7, got {record_size}")
    if len(cell_payload) != record_size * record_count:
        raise ValidationError(
            f"Cell payload length mismatch: expected {record_size * record_count}, "
            f"got {len(cell_payload)}"
        )
    verify_hash(cell_payload, str(cells.get("sha256", "")), "Cell payload")

    terrain_payload = decode_chunks(
        project_root,
        str(background.get("chunk_template", "")),
        int(background.get("chunk_count", 0)),
    )
    if str(background.get("format", "")).lower() != "png":
        raise ValidationError("Runtime terrain must use lossless PNG")
    terrain_width, terrain_height = png_dimensions(terrain_payload)
    verify_hash(
        terrain_payload, str(background.get("sha256", "")), "Terrain PNG"
    )
    render_size = manifest.get("render_size", [])
    if not isinstance(render_size, list) or len(render_size) < 2:
        raise ValidationError("Runtime manifest render_size is invalid")
    if [terrain_width, terrain_height] != [int(render_size[0]), int(render_size[1])]:
        raise ValidationError(
            f"Terrain PNG size {terrain_width}x{terrain_height} does not match "
            f"render_size {render_size}"
        )

    try:
        resource_payload = base64.b64decode(
            str(resources.get("encoded", "")), validate=True
        )
    except ValueError as exc:
        raise ValidationError(f"Invalid resource record Base64: {exc}") from exc
    resource_record_size = int(resources.get("record_size", 0))
    resource_count = int(resources.get("count", 0))
    if resource_record_size != 8:
        raise ValidationError(
            f"Resource record size must be 8, got {resource_record_size}"
        )
    if len(resource_payload) != resource_record_size * resource_count:
        raise ValidationError(
            f"Resource payload length mismatch: expected "
            f"{resource_record_size * resource_count}, got {len(resource_payload)}"
        )

    return {
        "cells": record_count,
        "resources": resource_count,
        "terrain_width": terrain_width,
        "terrain_height": terrain_height,
    }


def validate_resource_manifest(project_root: Path, path: Path) -> dict[str, int]:
    manifest = load_json(path)
    if manifest.get("format") != "ra2-resource-atlas-v2":
        raise ValidationError(
            f"Unsupported resource atlas format: {manifest.get('format')!r}"
        )
    if str(manifest.get("image_format", "")).lower() != "png":
        raise ValidationError("Corrected RA2 resource atlas must use PNG")
    payload = decode_chunks(
        project_root,
        str(manifest.get("chunk_template", "")),
        int(manifest.get("chunk_count", 0)),
    )
    width, height = png_dimensions(payload)
    verify_hash(payload, str(manifest.get("sha256", "")), "Resource atlas PNG")
    expected_size = manifest.get("size", [])
    if not isinstance(expected_size, list) or len(expected_size) < 2:
        raise ValidationError("Resource atlas size is invalid")
    if [width, height] != [int(expected_size[0]), int(expected_size[1])]:
        raise ValidationError(
            f"Resource atlas PNG size {width}x{height} does not match {expected_size}"
        )

    assets = manifest.get("assets")
    if not isinstance(assets, dict):
        raise ValidationError("Resource atlas assets must be an object")
    required = ["tib_01_00", "tib_20_11", "tibtre01_00", "tibtre01_10"]
    for asset_id in required:
        if asset_id not in assets:
            raise ValidationError(f"Corrected resource atlas is missing {asset_id}")
    for asset_id, raw_definition in assets.items():
        if not isinstance(raw_definition, dict):
            raise ValidationError(f"Asset definition must be an object: {asset_id}")
        region = raw_definition.get("region", [])
        if not isinstance(region, list) or len(region) != 4:
            raise ValidationError(f"Asset region is invalid: {asset_id}")
        x, y, asset_width, asset_height = map(int, region)
        if x < 0 or y < 0 or asset_width <= 0 or asset_height <= 0:
            raise ValidationError(f"Asset region has invalid dimensions: {asset_id}")
        if x + asset_width > width or y + asset_height > height:
            raise ValidationError(f"Asset region exceeds atlas bounds: {asset_id}")

    rules = manifest.get("palette_rules", {})
    expected_rules = {
        "TIB*.TEM": "temperat.pal",
        "GEM*.TEM": "temperat.pal",
        "TIBTRE*.TEM": "unittem.pal",
    }
    if rules != expected_rules:
        raise ValidationError(
            f"Palette rules mismatch: expected {expected_rules}, got {rules}"
        )
    return {"assets": len(assets), "width": width, "height": height}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate committed RA2 Godot runtime bundles"
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--runtime-manifest", default="data/ra2_maps/mymap1_runtime.json"
    )
    parser.add_argument(
        "--resource-manifest",
        default="data/ra2_embedded/temperate_resources_v2.json",
    )
    arguments = parser.parse_args()
    project_root = arguments.project_root.resolve()
    try:
        runtime = validate_runtime_manifest(
            project_root, project_root / arguments.runtime_manifest
        )
        resources = validate_resource_manifest(
            project_root, project_root / arguments.resource_manifest
        )
    except ValidationError as exc:
        parser.error(str(exc))
    print(
        "RA2 runtime bundle valid: "
        f"{runtime['cells']} cells, {runtime['resources']} resource overlays, "
        f"terrain {runtime['terrain_width']}x{runtime['terrain_height']}, "
        f"{resources['assets']} corrected texture frames"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
