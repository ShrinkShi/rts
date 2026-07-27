from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
from typing import Any

IDX_MAGIC = b"GABA"
FORMAT_INFO = {
    2: ("pcm", 1, 8),
    3: ("pcm", 2, 8),
    6: ("pcm", 1, 16),
    7: ("pcm", 2, 16),
    12: ("ima_adpcm", 1, 4),
    13: ("ima_adpcm", 2, 4),
}

_IMA_INDEX_TABLE = (
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8,
)
_IMA_STEP_TABLE = (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
    143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
    494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
    1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
    4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623,
    27086, 29794, 32767,
)


@dataclass(frozen=True)
class AudioEntry:
    name: str
    offset: int
    size: int
    sample_rate: int
    format_code: int
    chunk_size: int
    index: int

    @property
    def codec(self) -> str:
        return FORMAT_INFO.get(self.format_code, ("unknown", 0, 0))[0]

    @property
    def channels(self) -> int:
        return FORMAT_INFO.get(self.format_code, ("unknown", 0, 0))[1]

    @property
    def bits_per_sample(self) -> int:
        return FORMAT_INFO.get(self.format_code, ("unknown", 0, 0))[2]

    def to_dict(self, resource_path: str | None = None) -> dict[str, Any]:
        result = {
            "name": self.name,
            "offset": self.offset,
            "size": self.size,
            "sample_rate": self.sample_rate,
            "format_code": self.format_code,
            "codec": self.codec,
            "channels": self.channels,
            "bits_per_sample": self.bits_per_sample,
            "chunk_size": self.chunk_size,
            "index": self.index,
            # Godot only accepts uncompressed PCM as WAV import source. The original
            # BAG codec is kept above for provenance, while the generated source WAV
            # is normalized to signed 16-bit PCM.
            "godot_source_codec": "pcm_s16le",
            "godot_source_bits_per_sample": 16,
        }
        if resource_path:
            result["resource_path"] = resource_path
        return result


class AudioBag:
    def __init__(self, idx_path: str | Path, bag_path: str | Path):
        self.idx_path = Path(idx_path)
        self.bag_path = Path(bag_path)
        self.entries = self._read_index()
        self._bag_size = self.bag_path.stat().st_size
        self._validate_ranges()

    def _read_index(self) -> tuple[AudioEntry, ...]:
        data = self.idx_path.read_bytes()
        if len(data) < 12:
            raise ValueError("Audio IDX is truncated")
        magic, version, count = struct.unpack_from("<4sII", data, 0)
        if magic != IDX_MAGIC:
            raise ValueError(f"Invalid Audio IDX magic: {magic!r}")
        if version not in (1, 2):
            raise ValueError(f"Unsupported Audio IDX version: {version}")
        expected = 12 + count * 36
        if len(data) != expected:
            raise ValueError(f"Audio IDX size mismatch: expected {expected}, got {len(data)}")
        entries: list[AudioEntry] = []
        for index in range(count):
            offset = 12 + index * 36
            raw_name = data[offset:offset + 16].split(b"\0", 1)[0]
            name = raw_name.decode("ascii", errors="replace")
            bag_offset, size, rate, format_code, chunk_size = struct.unpack_from("<IIIII", data, offset + 16)
            entries.append(AudioEntry(name, bag_offset, size, rate, format_code, chunk_size, index))
        return tuple(entries)

    def _validate_ranges(self) -> None:
        for entry in self.entries:
            if entry.offset + entry.size > self._bag_size:
                raise ValueError(f"Audio entry exceeds BAG: {entry.name}")
            if entry.format_code not in FORMAT_INFO:
                raise ValueError(f"Unsupported audio format code {entry.format_code}: {entry.name}")

    @staticmethod
    def _riff_chunk(chunk_id: bytes, payload: bytes) -> bytes:
        result = chunk_id + struct.pack("<I", len(payload)) + payload
        if len(payload) & 1:
            result += b"\0"
        return result

    @classmethod
    def _pcm16_wav(cls, sample_rate: int, channels: int, pcm16: bytes) -> bytes:
        if channels not in (1, 2):
            raise ValueError(f"Unsupported channel count: {channels}")
        if len(pcm16) % (channels * 2) != 0:
            raise ValueError("PCM16 payload is not aligned to whole audio frames")
        block_align = channels * 2
        byte_rate = sample_rate * block_align
        fmt = struct.pack("<HHIIHH", 1, channels, sample_rate, byte_rate, block_align, 16)
        wave_payload = b"WAVE" + cls._riff_chunk(b"fmt ", fmt) + cls._riff_chunk(b"data", pcm16)
        return b"RIFF" + struct.pack("<I", len(wave_payload)) + wave_payload

    @staticmethod
    def _decode_ima_nibble(nibble: int, predictor: int, step_index: int) -> tuple[int, int]:
        step = _IMA_STEP_TABLE[step_index]
        # This form matches Microsoft IMA WAV decoding and FFmpeg exactly. Adding
        # separately shifted terms changes rounding and slowly drifts the waveform.
        difference = (((nibble & 7) * 2 + 1) * step) >> 3
        predictor = predictor - difference if nibble & 8 else predictor + difference
        predictor = max(-32768, min(32767, predictor))
        step_index = max(0, min(88, step_index + _IMA_INDEX_TABLE[nibble]))
        return predictor, step_index

    @classmethod
    def _decode_ima_adpcm(cls, raw_data: bytes, block_align: int, channels: int) -> bytes:
        if block_align <= 4 * channels:
            raise ValueError(f"Invalid IMA ADPCM block alignment: {block_align}")
        decoded_channels: list[list[int]] = [[] for _ in range(channels)]

        for block_offset in range(0, len(raw_data), block_align):
            block = raw_data[block_offset:block_offset + block_align]
            if len(block) < 4 * channels:
                break

            predictors: list[int] = []
            step_indices: list[int] = []
            for channel in range(channels):
                predictor, step_index, _reserved = struct.unpack_from("<hBB", block, channel * 4)
                predictors.append(predictor)
                step_indices.append(max(0, min(88, step_index)))
                decoded_channels[channel].append(predictor)

            payload = block[4 * channels:]
            if channels == 1:
                for byte in payload:
                    for nibble in (byte & 0x0F, byte >> 4):
                        predictors[0], step_indices[0] = cls._decode_ima_nibble(
                            nibble, predictors[0], step_indices[0]
                        )
                        decoded_channels[0].append(predictors[0])
            else:
                # Microsoft IMA WAV stereo stores four encoded bytes for the left
                # channel, then four for the right channel, repeating per block.
                payload_offset = 0
                while payload_offset < len(payload):
                    for channel in range(channels):
                        chunk = payload[payload_offset:payload_offset + 4]
                        payload_offset += len(chunk)
                        for byte in chunk:
                            for nibble in (byte & 0x0F, byte >> 4):
                                predictors[channel], step_indices[channel] = cls._decode_ima_nibble(
                                    nibble, predictors[channel], step_indices[channel]
                                )
                                decoded_channels[channel].append(predictors[channel])
                        if payload_offset >= len(payload) and len(chunk) < 4:
                            break

        frame_count = min((len(samples) for samples in decoded_channels), default=0)
        output = bytearray(frame_count * channels * 2)
        write_offset = 0
        for frame_index in range(frame_count):
            for channel in range(channels):
                struct.pack_into("<h", output, write_offset, decoded_channels[channel][frame_index])
                write_offset += 2
        return bytes(output)

    @staticmethod
    def _decode_pcm(raw_data: bytes, bits: int) -> bytes:
        if bits == 16:
            if len(raw_data) & 1:
                raw_data = raw_data[:-1]
            return raw_data
        if bits == 8:
            output = bytearray(len(raw_data) * 2)
            for index, value in enumerate(raw_data):
                struct.pack_into("<h", output, index * 2, (value - 128) << 8)
            return bytes(output)
        raise ValueError(f"Unsupported PCM bit depth: {bits}")

    @classmethod
    def wrap_wav(cls, entry: AudioEntry, raw_data: bytes) -> bytes:
        codec, channels, bits = FORMAT_INFO[entry.format_code]
        if codec == "pcm":
            pcm16 = cls._decode_pcm(raw_data, bits)
        else:
            pcm16 = cls._decode_ima_adpcm(raw_data, entry.chunk_size, channels)
        return cls._pcm16_wav(entry.sample_rate, channels, pcm16)

    @classmethod
    def normalize_wav_to_pcm16(cls, wave_data: bytes) -> tuple[bytes, dict[str, int | str]]:
        if len(wave_data) < 12 or wave_data[:4] != b"RIFF" or wave_data[8:12] != b"WAVE":
            raise ValueError("Not a RIFF/WAVE file")

        fmt_payload: bytes | None = None
        audio_payload: bytes | None = None
        offset = 12
        while offset + 8 <= len(wave_data):
            chunk_id = wave_data[offset:offset + 4]
            chunk_size = struct.unpack_from("<I", wave_data, offset + 4)[0]
            offset += 8
            chunk = wave_data[offset:offset + chunk_size]
            if len(chunk) != chunk_size:
                raise ValueError(f"Truncated WAV chunk: {chunk_id!r}")
            if chunk_id == b"fmt ":
                fmt_payload = chunk
            elif chunk_id == b"data":
                audio_payload = chunk
            offset += chunk_size + (chunk_size & 1)

        if fmt_payload is None or len(fmt_payload) < 16 or audio_payload is None:
            raise ValueError("WAV is missing fmt or data chunk")

        format_tag, channels, sample_rate, _byte_rate, block_align, bits = struct.unpack_from(
            "<HHIIHH", fmt_payload, 0
        )
        if format_tag == 1:
            pcm16 = cls._decode_pcm(audio_payload, bits)
            original_codec = f"pcm{bits}"
        elif format_tag == 0x11:
            pcm16 = cls._decode_ima_adpcm(audio_payload, block_align, channels)
            original_codec = "ima_adpcm"
        else:
            raise ValueError(f"Unsupported WAV format tag: {format_tag}")

        return cls._pcm16_wav(sample_rate, channels, pcm16), {
            "original_codec": original_codec,
            "sample_rate": sample_rate,
            "channels": channels,
            "godot_source_codec": "pcm_s16le",
            "godot_source_bits_per_sample": 16,
        }

    def extract(
        self, output_dir: str | Path, *, resource_prefix: str,
        source_bank: str = "audio", source_priority: int = 0,
    ) -> list[dict[str, Any]]:
        target = Path(output_dir)
        target.mkdir(parents=True, exist_ok=True)
        bag = self.bag_path.read_bytes()
        manifest: list[dict[str, Any]] = []
        seen: dict[str, int] = {}
        for entry in self.entries:
            stem = entry.name.casefold() or f"unnamed_{entry.index:04d}"
            duplicate_index = seen.get(stem, 0)
            seen[stem] = duplicate_index + 1
            filename = f"{stem}.wav" if duplicate_index == 0 else f"{stem}_{duplicate_index}.wav"
            raw = bag[entry.offset:entry.offset + entry.size]
            (target / filename).write_bytes(self.wrap_wav(entry, raw))
            record = entry.to_dict(f"{resource_prefix.rstrip('/')}/{filename}")
            record["source"] = "audio_bag"
            record["source_bank"] = source_bank
            record["source_priority"] = source_priority
            manifest.append(record)
        return manifest


def copy_standalone_wavs(
    source_dir: str | Path, output_dir: str | Path, *, resource_prefix: str,
    source_bank: str = "audio", source_priority: int = 0,
) -> list[dict[str, Any]]:
    source = Path(source_dir)
    target = Path(output_dir)
    target.mkdir(parents=True, exist_ok=True)
    manifest: list[dict[str, Any]] = []
    for path in sorted(source.glob("*.wav"), key=lambda item: item.name.casefold()):
        filename = path.name.casefold()
        destination = target / filename
        normalized, metadata = AudioBag.normalize_wav_to_pcm16(path.read_bytes())
        destination.write_bytes(normalized)
        manifest.append({
            "name": path.stem.casefold(),
            "filename": filename,
            "size": len(normalized),
            "resource_path": f"{resource_prefix.rstrip('/')}/{filename}",
            "source": "standalone_wav",
            "source_bank": source_bank,
            "source_priority": source_priority,
            **metadata,
        })
    return manifest
