from __future__ import annotations

import base64
import struct
import tempfile
import unittest
from pathlib import Path

from ra2_ini import IniDocument, RA2MapError, concatenated_section_value
from ra2_map_importer import import_map, parse_iso_tiles, parse_overlays
from ra2_pack_codecs import (
    ISO_TILE_STRUCT,
    OVERLAY_DIMENSION,
    decode_format5_blocks,
    decode_format80,
    encode_format5_literal_blocks,
    encode_format80_literals,
)


def section(name: str, payload: bytes) -> str:
    encoded = base64.b64encode(payload).decode("ascii")
    chunks = [encoded[index : index + 70] for index in range(0, len(encoded), 70)]
    return "\n".join([f"[{name}]", *(f"{i + 1}={chunk}" for i, chunk in enumerate(chunks)), ""])


class IniTests(unittest.TestCase):
    def test_numeric_pack_lines_are_sorted(self) -> None:
        document = IniDocument.from_bytes(b"[Pack]\n2=BB\n1=AA\n10=CC\n")
        self.assertEqual(concatenated_section_value(document, "Pack"), "AABBCC")


class CodecTests(unittest.TestCase):
    def test_format80_literal_stream(self) -> None:
        source = bytes(range(130))
        encoded = encode_format80_literals(source)
        self.assertEqual(decode_format80(encoded, expected_size=len(source)), source)

    def test_format5_lzo_literal_blocks(self) -> None:
        source = bytes((index * 17) & 0xFF for index in range(475))
        # 475 splits into 238 + 237; both are valid literal-only LZO streams.
        encoded = encode_format5_literal_blocks(source, compression_format=5)
        self.assertEqual(decode_format5_blocks(encoded, expected_size=len(source)), source)


class MapTests(unittest.TestCase):
    def make_document(self, new_ini_format: int = 4) -> IniDocument:
        tile_bytes = b"".join(
            [
                ISO_TILE_STRUCT.pack(10, 12, 1234, 2, 3, 0),
                ISO_TILE_STRUCT.pack(11, 12, 1235, 1, 3, 7),
            ]
        ) + b"\x00\x00\x00\x00"
        iso_pack = encode_format5_literal_blocks(tile_bytes, compression_format=5)

        cell_count = OVERLAY_DIMENSION * OVERLAY_DIMENSION
        if new_ini_format >= 5:
            overlay_ids = bytearray(b"\xFF\xFF" * cell_count)
            struct.pack_into("<H", overlay_ids, (12 * OVERLAY_DIMENSION + 10) * 2, 301)
        else:
            overlay_ids = bytearray(b"\xFF" * cell_count)
            overlay_ids[12 * OVERLAY_DIMENSION + 10] = 27
        overlay_frames = bytearray(cell_count)
        overlay_frames[12 * OVERLAY_DIMENSION + 10] = 6
        overlay_pack = encode_format5_literal_blocks(bytes(overlay_ids), compression_format=80)
        overlay_data_pack = encode_format5_literal_blocks(bytes(overlay_frames), compression_format=80)

        text = "\n".join(
            [
                "[Map]",
                "Size=0,0,4,4",
                "LocalSize=1,1,2,2",
                "Theater=TEMPERATE",
                "",
                "[Basic]",
                f"NewINIFormat={new_ini_format}",
                "",
                section("IsoMapPack5", iso_pack),
                section("OverlayPack", overlay_pack),
                section("OverlayDataPack", overlay_data_pack),
                "[Waypoints]",
                "0=12010",
                "",
                "[Terrain]",
                "12010=TREE01",
                "",
            ]
        )
        return IniDocument.from_bytes(text.encode("ascii"))

    def test_iso_tiles_preserve_original_fields(self) -> None:
        tiles = parse_iso_tiles(self.make_document(), width=4, height=4)
        self.assertEqual(tiles[0]["tile_index"], 1234)
        self.assertEqual(tiles[0]["sub_tile"], 2)
        self.assertEqual(tiles[0]["level"], 3)
        self.assertEqual(tiles[1]["ice_growth"], 7)

    def test_overlay_pack_legacy_and_extended_ids(self) -> None:
        legacy = parse_overlays(self.make_document(4), 4)
        extended = parse_overlays(self.make_document(5), 5)
        self.assertEqual(legacy, [{"rx": 10, "ry": 12, "overlay_id": 27, "frame": 6}])
        self.assertEqual(extended, [{"rx": 10, "ry": 12, "overlay_id": 301, "frame": 6}])

    def test_import_map_keeps_canonical_source_contract(self) -> None:
        document = self.make_document(4)
        lines: list[str] = []
        for name, entries in document.sections.items():
            if not name:
                continue
            lines.append(f"[{name}]")
            lines.extend(f"{entry.key}={entry.value}" for entry in entries)
            lines.append("")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.map"
            path.write_text("\n".join(lines), encoding="ascii")
            result = import_map(path)
        self.assertTrue(result["canonical_source_required"])
        self.assertEqual(result["map"]["theater"], "TEMPERATE")
        self.assertEqual(result["waypoints"], [{"id": 0, "rx": 10, "ry": 12}])
        self.assertEqual(result["terrain"], [{"rx": 10, "ry": 12, "type": "TREE01"}])

    def test_rejects_incomplete_overlay_pair(self) -> None:
        document = self.make_document(4)
        del document.sections["OverlayDataPack"]
        with self.assertRaises(RA2MapError):
            parse_overlays(document, 4)


if __name__ == "__main__":
    unittest.main()
