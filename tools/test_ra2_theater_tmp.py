from __future__ import annotations

import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from ra2_ini import IniDocument, RA2MapError
from ra2_map_enrichment import enrich_imported_map
from ra2_theater import ArchiveStack, CaseInsensitiveZip, TheaterCatalog
from ra2_tmp import CELL_HEADER, FILE_HEADER, TmpFile, unpack_diamond


def make_tmp(
    *,
    terrain_type: int = 13,
    ramp_type: int = 0,
    height: int = 0,
    extra: bool = True,
) -> bytes:
    width, image_height = 60, 30
    packed_size = width * image_height // 2
    main = bytes((index % 255) + 1 for index in range(packed_size))
    z_data = bytes((index * 3) & 0xFF for index in range(packed_size))
    extra_pixels = b"\x01\x02\x03\x04\x05\x06" if extra else b""
    extra_z = b"\x10\x11\x12\x13\x14\x15" if extra else b""
    pointer = FILE_HEADER.size + 4
    main_offset = CELL_HEADER.size
    z_offset = main_offset + len(main)
    extra_offset = z_offset + len(z_data)
    extra_z_offset = extra_offset + len(extra_pixels)
    flags = 2 | (1 if extra else 0)
    header = CELL_HEADER.pack(
        0,
        0,
        extra_offset if extra else 0xCDCDCDCD,
        z_offset,
        extra_z_offset if extra else 0xCDCDCDCD,
        -1 if extra else -842150451,
        -2 if extra else -842150451,
        3 if extra else 0xCDCDCDCD,
        2 if extra else 0xCDCDCDCD,
        flags,
        height,
        terrain_type,
        ramp_type,
        10,
        20,
        30,
        40,
        50,
        60,
    )
    return b"".join(
        [
            FILE_HEADER.pack(1, 1, width, image_height),
            struct.pack("<I", pointer),
            header,
            main,
            z_data,
            extra_pixels,
            extra_z,
        ]
    )


class TmpTests(unittest.TestCase):
    def test_reads_main_extra_z_height_land_and_ramp(self) -> None:
        tmp = TmpFile.from_bytes(
            make_tmp(terrain_type=15, ramp_type=7, height=4),
            source_name="fixture.tem",
        )
        cell = tmp.cell(0)
        self.assertEqual((tmp.block_image_width, tmp.block_image_height), (60, 30))
        self.assertEqual((cell.height, cell.terrain_type, cell.ramp_type), (4, 15, 7))
        self.assertTrue(cell.has_extra_data)
        self.assertTrue(cell.has_z_data)
        self.assertEqual(
            (cell.extra_x, cell.extra_y, cell.extra_width, cell.extra_height),
            (-1, -2, 3, 2),
        )
        self.assertEqual(len(cell.pixels), 900)
        self.assertEqual(len(cell.z_data), 900)
        self.assertEqual(cell.extra_pixels, b"\x01\x02\x03\x04\x05\x06")
        self.assertEqual(cell.extra_z_data, b"\x10\x11\x12\x13\x14\x15")
        unpacked = unpack_diamond(cell.pixels, 60, 30)
        self.assertEqual(len(unpacked), 1800)
        self.assertEqual(sum(1 for value in unpacked if value != 0), 900)

    def test_rejects_empty_sub_tile(self) -> None:
        payload = FILE_HEADER.pack(1, 1, 60, 30) + struct.pack("<I", 0)
        tmp = TmpFile.from_bytes(payload, "empty.tem")
        with self.assertRaises(RA2MapError):
            tmp.cell(0)


class TheaterTests(unittest.TestCase):
    def make_ini(self) -> IniDocument:
        return IniDocument.from_bytes(
            b"""
[General]
RampBase=1
CliffSet=1
[TileSet0000]
SetName=Clear
FileName=Clear
TilesInSet=1
[TileSet0001]
SetName=Cliff Set
FileName=Cliff
TilesInSet=2
AllowBurrowing=no
"""
        )

    def test_global_tile_index_resolves_to_tileset_and_filename(self) -> None:
        catalog = TheaterCatalog(self.make_ini())
        self.assertEqual(catalog.tile_count, 3)
        self.assertEqual(catalog.resolve(0).filename, "clear01.tem")
        resolved = catalog.resolve(2)
        self.assertEqual(
            (resolved.tile_set, resolved.ordinal, resolved.filename),
            (1, 2, "cliff02.tem"),
        )
        self.assertFalse(resolved.definition.allow_burrowing)

    def test_archive_stack_uses_optional_theater_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            primary = root / "isotemp.zip"
            optional = root / "temperat.zip"
            with zipfile.ZipFile(primary, "w") as archive:
                archive.writestr("CLEAR01.TEM", make_tmp(extra=False))
                archive.writestr("CLIFF01.TEM", make_tmp(terrain_type=15))
            with zipfile.ZipFile(optional, "w") as archive:
                archive.writestr("OvrPsB01.TeM", make_tmp(terrain_type=8))
            stack = ArchiveStack(
                [CaseInsensitiveZip(primary), CaseInsensitiveZip(optional)]
            )
            try:
                self.assertTrue(stack.has("clear01.tem"))
                self.assertTrue(stack.has("ovrpsb01.tem"))
                self.assertEqual(stack.source_for("ovrpsb01.tem"), "temperat.zip")
            finally:
                stack.close()

    def test_map_enrichment_preserves_map_level_and_adds_tmp_metadata(self) -> None:
        catalog = TheaterCatalog(self.make_ini())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "isotemp.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("clear01.tem", make_tmp(extra=False))
                archive.writestr("cliff01.tem", make_tmp(terrain_type=15, height=4))
                archive.writestr(
                    "cliff02.tem",
                    make_tmp(terrain_type=15, ramp_type=3, height=2),
                )
            stack = ArchiveStack([CaseInsensitiveZip(path)])
            try:
                imported = {
                    "format": "ra2yr-map-cache-v1",
                    "tiles": [
                        {
                            "rx": 5,
                            "ry": 7,
                            "tile_index": 2,
                            "sub_tile": 0,
                            "level": 8,
                        }
                    ],
                }
                result = enrich_imported_map(imported, catalog, stack)
            finally:
                stack.close()
        tile = result["tiles"][0]
        self.assertEqual(tile["level"], 8)
        self.assertEqual(tile["theater"]["tmp_height"], 2)
        self.assertEqual(tile["theater"]["ramp_type"], 3)
        self.assertEqual(tile["theater"]["filename"], "cliff02.tem")
        self.assertEqual(result["format"], "ra2yr-map-cache-v2")


if __name__ == "__main__":
    unittest.main()
