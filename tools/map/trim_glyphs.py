"""Shrinks the map's label fonts to the characters the map can show.

The fonts come as 256 files per font, one for every block of 256 Unicode
characters (tools/map/fetch_glyphs.py). The map area only ever shows a few
of those blocks, so most of the files are dead weight: about 12 MB of them.

This script reads every label in the offline map archive, works out which
blocks those labels need, keeps those files, and replaces every other file
with a tiny empty one. An empty file, rather than no file, means a character
the map has no glyph for is simply not drawn; a missing file would make
MapLibre fail the whole request.

Blocks always kept, whatever the archive holds, for the names admins type
for stops and buses: Latin (0-511), Bangla (2304-2559) and general
punctuation (8192-8447).

Run after fetch_glyphs.py and after every rebuild of the archive, from the
project root:

    tools/map/.venv/Scripts/python tools/map/trim_glyphs.py
"""

from __future__ import annotations

import gzip
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from extract_basemap import ARCHIVE_NAME, OUTPUT_DIR  # noqa: E402
from inspect_basemap import decode_layer, fields  # noqa: E402
from pmtiles.reader import MmapSource, Reader, all_tiles  # noqa: E402

FONTS_DIR = OUTPUT_DIR / "fonts"
ALWAYS_KEPT = {0, 256, 2304, 8192}

# A file smaller than this is already an empty placeholder.
PLACEHOLDER_MAX_BYTES = 64


def shown_label(properties: dict) -> str | None:
    """The text the styles draw for a feature: English name, else local."""
    for key in ("name:en", "name"):
        value = properties.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def blocks_in_archive() -> tuple[set[int], int]:
    blocks: set[int] = set()
    labels = 0
    with open(OUTPUT_DIR / ARCHIVE_NAME, "rb") as handle:
        reader = Reader(MmapSource(handle))
        for _, tile in all_tiles(reader.get_bytes):
            for number, _, value in fields(gzip.decompress(tile)):
                if number != 3:
                    continue
                _, features = decode_layer(value)
                for _, properties in features:
                    label = shown_label(properties)
                    if label is None:
                        continue
                    labels += 1
                    blocks.update(ord(character) // 256 * 256 for character in label)
    return blocks, labels


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def placeholder(font: str, block: str) -> bytes:
    """A valid glyph file that holds no glyphs."""
    name = font.encode()
    range_ = block.encode()
    stack = b"\x0a" + varint(len(name)) + name + b"\x12" + varint(len(range_)) + range_
    return b"\x0a" + varint(len(stack)) + stack


def main() -> int:
    needed, labels = blocks_in_archive()
    kept = needed | ALWAYS_KEPT
    print(f"{labels} labels in {ARCHIVE_NAME} use blocks {sorted(needed)}")
    print(f"keeping blocks {sorted(kept)}")

    before = after = 0
    for font_dir in sorted(path for path in FONTS_DIR.iterdir() if path.is_dir()):
        files = sorted(font_dir.glob("*.pbf"))
        if len(files) != 256:
            print(f"ERROR: {font_dir.name} has {len(files)} files, expected 256")
            return 1
        for file in files:
            size = file.stat().st_size
            before += size
            start = int(file.stem.split("-")[0])
            if start in kept:
                # Kept as fetched, even if the font has few glyphs there
                # (the italic font has no Bangla, for example).
                after += size
                continue
            stub = placeholder(font_dir.name, file.stem)
            if size > PLACEHOLDER_MAX_BYTES:
                file.write_bytes(stub)
            after += len(stub)
    print(f"fonts: {before / 1e6:.2f} MB -> {after / 1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
