from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
import wave

from ra2_formats.cli import import_wav
from ra2_formats.hva import HvaFile
from ra2_formats.palette import Palette
from ra2_formats.shp_ts import ShpTsFile
from ra2_formats.vxl import VxlFile


ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ROOT / "assets" / "ra2_sources" / "samples"


@unittest.skipUnless(SAMPLES.exists(), "Local RA2 sample assets are not installed")
class RA2FormatSmokeTests(unittest.TestCase):
    def test_shp_ts_samples(self) -> None:
        gi = ShpTsFile(SAMPLES / "ggi.shp")
        self.assertEqual((gi.width, gi.height, gi.frame_count), (94, 78, 744))
        decoded = gi.decode_indices(0)
        self.assertEqual(len(decoded), gi.width * gi.height)
        self.assertGreater(sum(value != 0 for value in decoded), 0)

        power = ShpTsFile(SAMPLES / "ygpowr.shp")
        self.assertEqual((power.width, power.height, power.frame_count), (174, 142, 6))
        image = power.decode_image(0, Palette.from_file(SAMPLES / "unit_fallback.pal"))
        self.assertEqual(image.size, (174, 142))
        self.assertIsNotNone(image.getbbox())

    def test_vxl_hva_samples(self) -> None:
        expected = {
            "htk.vxl": 5230,
            "htktur.vxl": 799,
            "htkbarl.vxl": 155,
        }
        for filename, voxel_count in expected.items():
            model = VxlFile(SAMPLES / filename)
            self.assertEqual(len(model.sections), 1)
            self.assertEqual(len(model.sections[0].voxels), voxel_count)

        for filename in ("htk.hva", "htktur.hva", "htkbarl.hva"):
            animation = HvaFile(SAMPLES / filename)
            self.assertGreaterEqual(animation.frame_count, 1)
            self.assertEqual(animation.section_count, 1)
            self.assertEqual(len(animation.matrix(0, 0)), 12)

    def test_generated_manifest_and_resources(self) -> None:
        output = ROOT / "assets" / "ra2_imported"
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest["assets"]), 3)
        self.assertTrue((output / "ggi" / "sprite_frames.tres").exists())
        self.assertTrue((output / "htk" / "body_frames.tres").exists())
        self.assertTrue((output / "htk" / "turret_frames.tres").exists())
        self.assertTrue((output / "ygpowr" / "shp_resource.tres").exists())

    def test_wav_copy_pipeline(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            source = temp / "test.wav"
            with wave.open(str(source), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(8000)
                wav_file.writeframes(b"\x00\x00" * 32)
            output = ROOT / "assets" / "ra2_imported" / "_wav_test"
            result = import_wav(source, output, ROOT)
            try:
                self.assertTrue((output / "test.wav").exists())
                self.assertEqual(result["type"], "wav")
            finally:
                if (output / "test.wav").exists():
                    (output / "test.wav").unlink()
                output.rmdir()


if __name__ == "__main__":
    unittest.main()
