from __future__ import annotations

from ra2_theater import ArchiveReader, TheaterCatalog


def enrich_imported_map(
    imported: dict[str, object],
    catalog: TheaterCatalog,
    archive: ArchiveReader,
) -> dict[str, object]:
    """Attach exact Temperat.ini/TMP metadata to imported IsoMapPack5 cells."""
    tmp_cache = {}
    resolved_cache = {}
    enriched_tiles = []
    used_files: dict[str, str] = {}

    for raw_tile in imported.get("tiles", []):
        tile = dict(raw_tile)
        tile_index = int(tile["tile_index"])
        sub_tile = int(tile["sub_tile"])

        resolved = resolved_cache.get(tile_index)
        if resolved is None:
            resolved = catalog.resolve(tile_index)
            resolved_cache[tile_index] = resolved

        tmp = tmp_cache.get(tile_index)
        if tmp is None:
            tmp = catalog.load_tmp(tile_index, archive)
            tmp_cache[tile_index] = tmp

        cell = tmp.cell(sub_tile)
        used_files[resolved.filename] = archive.source_for(resolved.filename)
        tile["theater"] = {
            "tile_set": resolved.tile_set,
            "tile_set_name": resolved.definition.name,
            "tile_ordinal": resolved.ordinal,
            "filename": resolved.filename,
            "archive": used_files[resolved.filename],
            "block_width": tmp.block_width,
            "block_height": tmp.block_height,
            "sub_cell_x": cell.grid_x,
            "sub_cell_y": cell.grid_y,
            "cell_pixel_x": cell.x,
            "cell_pixel_y": cell.y,
            "tmp_height": cell.height,
            "terrain_type": cell.terrain_type,
            "ramp_type": cell.ramp_type,
            "has_extra_data": cell.has_extra_data,
            "has_z_data": cell.has_z_data,
            "has_damaged_data": cell.has_damaged_data,
            "extra_x": cell.extra_x if cell.has_extra_data else 0,
            "extra_y": cell.extra_y if cell.has_extra_data else 0,
            "extra_width": cell.extra_width if cell.has_extra_data else 0,
            "extra_height": cell.extra_height if cell.has_extra_data else 0,
        }
        enriched_tiles.append(tile)

    result = dict(imported)
    result["format"] = "ra2yr-map-cache-v2"
    result["tiles"] = enriched_tiles
    result["theater_catalog"] = {
        "tile_set_count": len(catalog.tile_sets),
        "tile_count": catalog.tile_count,
        "extension": catalog.extension,
        "general": catalog.general,
        "used_tmp_files": [
            {"filename": filename, "archive": used_files[filename]}
            for filename in sorted(used_files)
        ],
    }
    return result
