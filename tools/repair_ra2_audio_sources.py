from __future__ import annotations

from pathlib import Path
import argparse
import struct

from ra2_pipeline.audio_bag import AudioBag


def wav_format(path: Path) -> tuple[int | None, int | None]:
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None, None
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset:offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        offset += 8
        if chunk_id == b"fmt " and chunk_size >= 16:
            return struct.unpack_from("<H", data, offset)[0], struct.unpack_from("<H", data, offset + 14)[0]
        offset += chunk_size + (chunk_size & 1)
    return None, None


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize RA2/YR WAV sources to Godot-compatible PCM16.")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()

    audio_root = args.project.resolve() / "assets" / "ra2_audio"
    if not audio_root.is_dir():
        raise SystemExit(f"Audio directory not found: {audio_root}")

    converted = 0
    skipped = 0
    for path in sorted(audio_root.rglob("*.wav")):
        format_tag, bits = wav_format(path)
        if format_tag == 1 and bits == 16:
            skipped += 1
            continue
        normalized, _metadata = AudioBag.normalize_wav_to_pcm16(path.read_bytes())
        path.write_bytes(normalized)
        converted += 1
        if converted % 250 == 0:
            print(f"Converted {converted} files...")

    print(f"Done. Converted: {converted}; already PCM16: {skipped}.")
    print("Close Godot and delete the project's .godot directory before reopening it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
