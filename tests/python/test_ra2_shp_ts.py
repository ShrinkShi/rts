from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from ra2_shp_ts import (  # noqa: E402
    FILE_HEADER,
    FRAME_HEADER,
    FLAG_HAS_TRANSPARENCY,
    FLAG_USES_RLE,
    ShpTsError,
    ShpTsFile,
    indexed_to_rgba,
)


class ShpTsTests(unittest.TestCase):
    def test_uncompressed_frame_is_placed_on_canvas(self) -> None:
        data_offset = FILE_HEADER.size + FRAME_HEADER.size
        payload = bytearray()
        payload += FILE_HEADER.pack(0, 4, 3, 1)
        payload += FRAME_HEADER.pack(
            1, 1, 2, 1, FLAG_HAS_TRANSPARENCY, 0, 0, 0, data_offset
        )
        payload += bytes([7, 8])
        shp = ShpTsFile.from_bytes(bytes(payload), "test.shp")
        self.assertEqual((shp.width, shp.height), (4, 3))
        self.assertEqual(
            shp.frames[0].pixels,
            bytes([0, 0, 0, 0, 0, 7, 8, 0, 0, 0, 0, 0]),
        )

    def test_rle_frame_decodes_transparent_runs(self) -> None:
        data_offset = FILE_HEADER.size + FRAME_HEADER.size
        line = bytes([0, 2, 9])
        encoded_line = struct.pack("<H", len(line) + 2) + line
        payload = bytearray()
        payload += FILE_HEADER.pack(0, 4, 1, 1)
        payload += FRAME_HEADER.pack(
            0,
            0,
            4,
            1,
            FLAG_HAS_TRANSPARENCY | FLAG_USES_RLE,
            0,
            0,
            0,
            data_offset,
        )
        payload += encoded_line
        shp = ShpTsFile.from_bytes(bytes(payload), "rle.shp")
        self.assertEqual(shp.frames[0].pixels, bytes([0, 0, 9, 0]))

    def test_invalid_bounds_are_rejected(self) -> None:
        data_offset = FILE_HEADER.size + FRAME_HEADER.size
        payload = FILE_HEADER.pack(0, 2, 2, 1) + FRAME_HEADER.pack(
            1, 1, 2, 2, 0, 0, 0, 0, data_offset
        ) + bytes(4)
        with self.assertRaises(ShpTsError):
            ShpTsFile.from_bytes(payload, "bad.shp")

    def test_indexed_to_rgba_uses_palette_alpha(self) -> None:
        palette = tuple((i, i, i, 0 if i == 0 else 255) for i in range(256))
        rgba = indexed_to_rgba(bytes([0, 2]), 2, 1, palette)
        self.assertEqual(rgba, bytes([0, 0, 0, 0, 2, 2, 2, 255]))


if __name__ == "__main__":
    unittest.main()
