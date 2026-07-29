from __future__ import annotations

import struct

from ra2_ini import RA2MapError
from ra2_lzo import LZOError, decompress_lzo1x

ISO_TILE_STRUCT = struct.Struct("<hhIBBB")
ISO_TILE_SIZE = ISO_TILE_STRUCT.size
OVERLAY_DIMENSION = 512


def decode_format80(data: bytes, expected_size: int | None = None) -> bytes:
    output = bytearray()
    cursor = 0

    def read_u8() -> int:
        nonlocal cursor
        if cursor >= len(data):
            raise RA2MapError("Format80 input overrun")
        value = data[cursor]
        cursor += 1
        return value

    def read_u16() -> int:
        nonlocal cursor
        if cursor + 2 > len(data):
            raise RA2MapError("Format80 input overrun")
        value = struct.unpack_from("<H", data, cursor)[0]
        cursor += 2
        return value

    while True:
        command = read_u8()
        if (command & 0x80) == 0:
            count = 3 + ((command & 0x70) >> 4)
            offset = ((command & 0x0F) << 8) | read_u8()
            source = len(output) - offset
            _copy_previous(output, source, count)
        elif (command & 0x40) == 0:
            count = command & 0x3F
            if count == 0:
                break
            if cursor + count > len(data):
                raise RA2MapError("Format80 literal run exceeds input")
            output.extend(data[cursor : cursor + count])
            cursor += count
        else:
            subcommand = command & 0x3F
            if subcommand == 0x3E:
                count = read_u16()
                value = read_u8()
                output.extend(bytes((value,)) * count)
            else:
                count = read_u16() if subcommand == 0x3F else 3 + subcommand
                source = read_u16()
                _copy_previous(output, source, count)
        if expected_size is not None and len(output) > expected_size:
            raise RA2MapError(
                f"Format80 output exceeds expected size {expected_size}: {len(output)}"
            )

    if expected_size is not None and len(output) != expected_size:
        raise RA2MapError(
            f"Format80 output size mismatch: expected {expected_size}, got {len(output)}"
        )
    return bytes(output)


def _copy_previous(output: bytearray, source: int, count: int) -> None:
    if source < 0 or source >= len(output):
        raise RA2MapError("Format80 look-behind overrun")
    for _ in range(count):
        if source >= len(output):
            raise RA2MapError("Format80 source overrun")
        output.append(output[source])
        source += 1


def decode_format5_blocks(
    data: bytes,
    *,
    expected_size: int | None = None,
    compression_format: int = 5,
) -> bytes:
    output = bytearray()
    cursor = 0
    while cursor < len(data):
        if cursor + 4 > len(data):
            raise RA2MapError("Format5 block header is truncated")
        compressed_size, decompressed_size = struct.unpack_from("<HH", data, cursor)
        cursor += 4
        if compressed_size == 0 or decompressed_size == 0:
            break
        if cursor + compressed_size > len(data):
            raise RA2MapError("Format5 block payload is truncated")
        compressed = data[cursor : cursor + compressed_size]
        cursor += compressed_size
        try:
            if compression_format == 80:
                block = decode_format80(compressed, expected_size=decompressed_size)
            elif compression_format == 5:
                block = decompress_lzo1x(compressed, expected_size=decompressed_size)
            else:
                raise RA2MapError(f"Unsupported Format5 compression type: {compression_format}")
        except LZOError as exc:
            raise RA2MapError(f"MiniLZO decode failed: {exc}") from exc
        output.extend(block)
        if expected_size is not None and len(output) > expected_size:
            raise RA2MapError(
                f"Format5 output exceeds expected size {expected_size}: {len(output)}"
            )
    if expected_size is not None and len(output) != expected_size:
        raise RA2MapError(
            f"Format5 output size mismatch: expected {expected_size}, got {len(output)}"
        )
    return bytes(output)


def encode_format80_literals(data: bytes) -> bytes:
    """Deterministic literal-only encoder used by tests and future writer scaffolding."""
    output = bytearray()
    cursor = 0
    while cursor < len(data):
        count = min(63, len(data) - cursor)
        output.append(0x80 | count)
        output.extend(data[cursor : cursor + count])
        cursor += count
    output.append(0x80)
    return bytes(output)


def encode_lzo_literal_block(data: bytes) -> bytes:
    """Encode a single literal-only LZO1X stream for fixtures (4..238 bytes)."""
    if not 4 <= len(data) <= 238:
        raise ValueError("literal-only LZO fixture block must contain 4..238 bytes")
    return bytes((17 + len(data),)) + data + b"\x11\x00\x00"


def encode_format5_literal_blocks(data: bytes, compression_format: int) -> bytes:
    """Encode deterministic small fixture blocks; not a production map writer."""
    output = bytearray()
    cursor = 0
    max_chunk = 238 if compression_format == 5 else 4096
    while cursor < len(data):
        chunk = data[cursor : cursor + max_chunk]
        if compression_format == 5:
            if len(chunk) < 4:
                # Merge a short tail into the previous block by reducing the
                # previous split. Tests deliberately avoid impossible inputs.
                raise ValueError("LZO fixture tail must contain at least four bytes")
            encoded = encode_lzo_literal_block(chunk)
        elif compression_format == 80:
            encoded = encode_format80_literals(chunk)
        else:
            raise ValueError(f"Unsupported fixture format: {compression_format}")
        output.extend(struct.pack("<HH", len(encoded), len(chunk)))
        output.extend(encoded)
        cursor += len(chunk)
    return bytes(output)
