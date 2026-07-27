from __future__ import annotations

from typing import Any


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip() and item.strip().casefold() != "none"]


def as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().casefold() in {"yes", "true", "1", "on"}


def as_number(value: str | None, default: float | int | None = None) -> float | int | None:
    if value is None or not value.strip():
        return default
    raw = value.strip()
    if raw.endswith("%"):
        try:
            return float(raw[:-1]) / 100.0
        except ValueError:
            return default
    try:
        result = float(raw)
    except ValueError:
        return default
    return int(result) if result.is_integer() else result


def as_vector(value: str | None, length: int = 3) -> list[float] | None:
    values = split_csv(value)
    if len(values) < length:
        return None
    result: list[float] = []
    for item in values[:length]:
        try:
            result.append(float(item))
        except ValueError:
            return None
    return result


def normalized_scalar(value: str) -> Any:
    folded = value.strip().casefold()
    if folded in {"yes", "true", "no", "false"}:
        return as_bool(value)
    number = as_number(value, None)
    if number is not None:
        return number
    return value
