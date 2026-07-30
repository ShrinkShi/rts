from __future__ import annotations


class LZOError(ValueError):
    """Raised when an LZO1X stream is malformed or truncated."""


class LZO1XDecoder:
    """Pure-Python decoder for the MiniLZO LZO1X stream used by IsoMapPack5.

    It intentionally implements decompression only. Map writing will add a
    separate encoder and must not silently emit a different compression format.
    """

    def __init__(self, data: bytes, expected_size: int | None = None) -> None:
        self.data = data
        self.ip = 0
        self.output = bytearray()
        self.expected_size = expected_size

    def _read(self) -> int:
        if self.ip >= len(self.data):
            raise LZOError("LZO input overrun")
        value = self.data[self.ip]
        self.ip += 1
        return value

    def _copy_literals(self, count: int) -> None:
        if count < 0 or self.ip + count > len(self.data):
            raise LZOError("LZO literal run exceeds input")
        self.output.extend(self.data[self.ip : self.ip + count])
        self.ip += count
        self._guard_output()

    def _copy_match(self, source: int, count: int) -> None:
        if source < 0 or source >= len(self.output):
            raise LZOError("LZO look-behind overrun")
        for _ in range(count):
            if source >= len(self.output):
                raise LZOError("LZO match source overrun")
            self.output.append(self.output[source])
            source += 1
        self._guard_output()

    def _guard_output(self) -> None:
        if self.expected_size is not None and len(self.output) > self.expected_size:
            raise LZOError(
                f"LZO output exceeds expected size {self.expected_size}: {len(self.output)}"
            )

    def decode(self) -> bytes:
        if not self.data:
            return b""

        token = self._read()
        if token > 17:
            literal_count = token - 17
            if literal_count < 4:
                self._copy_literals(literal_count)
                token = self._read()
                if self._match(token):
                    return self._finish()
                skip_literal_run = False
            else:
                self._copy_literals(literal_count)
                skip_literal_run = True
        else:
            self.ip = 0
            skip_literal_run = False

        while True:
            if not skip_literal_run:
                token = self._read()
                if token >= 16:
                    if self._match(token):
                        break
                    continue
                if token == 0:
                    token = 0
                    while True:
                        value = self._read()
                        if value != 0:
                            token += 15 + value
                            break
                        token += 255
                self._copy_literals(token + 3)
            else:
                skip_literal_run = False

            token = self._read()
            if token < 16:
                source = len(self.output) - (1 + 0x0800) - (token >> 2) - (self._read() << 2)
                self._copy_match(source, 3)
                trailing = self.data[self.ip - 2] & 3
                if trailing == 0:
                    continue
                self._copy_literals(trailing)
                token = self._read()
            if self._match(token):
                break

        return self._finish()

    def _finish(self) -> bytes:
        if self.expected_size is not None and len(self.output) != self.expected_size:
            raise LZOError(
                f"LZO output size mismatch: expected {self.expected_size}, got {len(self.output)}"
            )
        return bytes(self.output)

    def _match_next(self, count: int) -> None:
        self._copy_literals(count)

    def _match(self, token: int) -> bool:
        while True:
            if self._decode_match(token):
                return True
            trailing = self.data[self.ip - 2] & 3
            if trailing == 0:
                return False
            self._copy_literals(trailing)
            token = self._read()

    def _decode_match(self, token: int) -> bool:
        if token >= 64:
            source = (
                len(self.output)
                - 1
                - ((token >> 2) & 7)
                - (self._read() << 3)
            )
            self._copy_match(source, (token >> 5) + 1)
            return False

        if token >= 32:
            length = token & 31
            if length == 0:
                while True:
                    value = self._read()
                    if value != 0:
                        length += 31 + value
                        break
                    length += 255
            low = self._read()
            high = self._read()
            source = len(self.output) - 1 - (low >> 2) - (high << 6)
            self._copy_match(source, length + 2)
            return False

        if token >= 16:
            source = len(self.output) - ((token & 8) << 11)
            length = token & 7
            if length == 0:
                while True:
                    value = self._read()
                    if value != 0:
                        length += 7 + value
                        break
                    length += 255
            low = self._read()
            high = self._read()
            source -= (low >> 2) + (high << 6)
            if source == len(self.output):
                return True
            source -= 0x4000
            self._copy_match(source, length + 2)
            return False

        source = len(self.output) - 1 - (token >> 2) - (self._read() << 2)
        self._copy_match(source, 2)
        return False


def decompress_lzo1x(data: bytes, expected_size: int | None = None) -> bytes:
    return LZO1XDecoder(data, expected_size=expected_size).decode()
