"""Summarises the contents of the offline basemap archive.

Prints, per vector layer, the feature count, geometry types, attribute keys
and the most common values of the attributes styles filter on. Used when
writing or checking the map styles against the real data.

Usage (from the project root):

    tools/map/.venv/Scripts/python tools/map/inspect_basemap.py [zoom]
"""

from __future__ import annotations

import gzip
import sys
from collections import Counter, defaultdict
from pathlib import Path

from pmtiles.reader import MmapSource, Reader, all_tiles

ARCHIVE = (
    Path(__file__).resolve().parents[2]
    / "assets"
    / "map"
    / "barishal_basemap_v2.pmtiles"
)
VALUE_KEYS = ("kind", "kind_detail", "script", "min_zoom", "sort_rank")
GEOMETRY_NAMES = {0: "unknown", 1: "point", 2: "line", 3: "polygon"}


def read_varint(data: bytes, position: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while True:
        byte = data[position]
        position += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, position
        shift += 7


def fields(data: bytes):
    """Yields (field number, wire type, value) for one protobuf message."""
    position = 0
    while position < len(data):
        key, position = read_varint(data, position)
        number, wire_type = key >> 3, key & 7
        if wire_type == 0:
            value, position = read_varint(data, position)
        elif wire_type == 2:
            length, position = read_varint(data, position)
            value = data[position : position + length]
            position += length
        elif wire_type == 5:
            value = data[position : position + 4]
            position += 4
        elif wire_type == 1:
            value = data[position : position + 8]
            position += 8
        else:
            raise ValueError(f"unsupported wire type {wire_type}")
        yield number, wire_type, value


def decode_value(data: bytes):
    import struct

    for number, _, value in fields(data):
        if number == 1:
            return value.decode("utf-8")
        if number == 2:
            return struct.unpack("<f", value)[0]
        if number == 3:
            return struct.unpack("<d", value)[0]
        if number in (4, 5):
            return value
        if number == 6:
            return (value >> 1) ^ -(value & 1)
        if number == 7:
            return bool(value)
    return None


def packed_varints(data: bytes) -> list[int]:
    values = []
    position = 0
    while position < len(data):
        value, position = read_varint(data, position)
        values.append(value)
    return values


def decode_layer(data: bytes):
    name = ""
    keys: list[str] = []
    values: list = []
    features: list[tuple[int, list[int]]] = []
    for number, _, value in fields(data):
        if number == 1:
            name = value.decode("utf-8")
        elif number == 2:
            geometry_type = 0
            tags: list[int] = []
            for f_number, _, f_value in fields(value):
                if f_number == 2:
                    tags = packed_varints(f_value)
                elif f_number == 3:
                    geometry_type = f_value
            features.append((geometry_type, tags))
        elif number == 3:
            keys.append(value.decode("utf-8"))
        elif number == 4:
            values.append(decode_value(value))
    decoded = []
    for geometry_type, tags in features:
        properties = {
            keys[tags[i]]: values[tags[i + 1]] for i in range(0, len(tags), 2)
        }
        decoded.append((geometry_type, properties))
    return name, decoded


def main() -> int:
    only_zoom = int(sys.argv[1]) if len(sys.argv) > 1 else None

    counts: Counter = Counter()
    geometries: dict[str, Counter] = defaultdict(Counter)
    keys: dict[str, Counter] = defaultdict(Counter)
    value_counts: dict[tuple[str, str], Counter] = defaultdict(Counter)
    samples: dict[str, list] = defaultdict(list)

    with open(ARCHIVE, "rb") as handle:
        reader = Reader(MmapSource(handle))
        print("header:", {k: reader.header()[k] for k in ("min_zoom", "max_zoom")})
        for (zoom, _, _), tile in all_tiles(reader.get_bytes):
            if only_zoom is not None and zoom != only_zoom:
                continue
            for number, _, value in fields(gzip.decompress(tile)):
                if number != 3:
                    continue
                layer, features = decode_layer(value)
                for geometry_type, properties in features:
                    counts[layer] += 1
                    geometries[layer][GEOMETRY_NAMES[geometry_type]] += 1
                    for key, item in properties.items():
                        keys[layer][key] += 1
                        if key in VALUE_KEYS:
                            value_counts[(layer, key)][item] += 1
                    if "name" in properties and len(samples[layer]) < 6:
                        samples[layer].append(
                            {
                                k: v
                                for k, v in properties.items()
                                if k.startswith("name") or k in ("kind", "script")
                            }
                        )

    for layer in sorted(counts):
        print(f"\n== {layer}: {counts[layer]} features, {dict(geometries[layer])}")
        print("   keys:", ", ".join(f"{k}({n})" for k, n in keys[layer].most_common(40)))
        for key in VALUE_KEYS:
            if (layer, key) in value_counts:
                top = value_counts[(layer, key)].most_common(30)
                print(f"   {key}:", ", ".join(f"{v}({n})" for v, n in top))
        for sample in samples[layer][:4]:
            print("   sample:", sample)
    return 0


if __name__ == "__main__":
    sys.exit(main())
