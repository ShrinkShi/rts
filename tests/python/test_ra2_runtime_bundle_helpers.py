from __future__ import annotations

import base64
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from build_ra2_runtime_bundle import (  # noqa: E402
    PNG_SIGNATURE,
    alpha_blit,
    encode_png_rgba,
    overlay_kind,
    write_base64_chunks,
)


class RuntimeBundleHelperTests(unittest.TestCase):
    def test_png_encoder_writes_valid_rgba_scanline(self) -> None:
        payload = encode_png_rgba(1, 1, bytes([10, 20, 30, 255]))
        self.assertTrue(payload.startswith(PNG_SIGNATURE))
        position = len(PNG_SIGNATURE)
        chunks: dict[bytes, bytes] = {}
        while position < len(payload):
            length = struct.unpack_from(">I", payload, position)[0]
            kind = payload[position + 4 : position + 8]
            data = payload[position + 8 : position + 8 + length]
            chunks[kind] = chunks.get(kind, b"") + data
            position += 12 + length
        self.assertEqual(
            zlib.decompress(chunks[b"IDAT"]), bytes([0, 10, 20, 30, 255])
        )

    def test_alpha_blit_overwrites_opaque_pixel(self) -> None:
        destination = bytearray(2 * 4)
        alpha_blit(destination, 2, 1, bytes([1, 2, 3, 255]), 1, 1, 1, 0)
        self.assertEqual(
            destination, bytearray([0, 0, 0, 0, 1, 2, 3, 255])
        )

    def test_resource_ranges_match_runtime_asset_ids(self) -> None:
        self.assertEqual(overlay_kind(105), 1)
        self.assertEqual(overlay_kind(124), 1)
        self.assertEqual(overlay_kind(28), 2)
        self.assertEqual(overlay_kind(39), 2)
        self.assertEqual(overlay_kind(104), 0)

    def test_base64_chunks_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            count = write_base64_chunks(
                b"0123456789" * 20,
                output,
                "sample",
                chunk_characters=16,
            )
            encoded = "".join(
                (output / f"sample_{index:02d}.b64").read_text().strip()
                for index in range(count)
            )
            self.assertEqual(base64.b64decode(encoded), b"0123456789" * 20)


if __name__ == "__main__":
    unittest.main()
