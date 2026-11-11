"""Looks up possible positions for the official stop names.

The official schedule names its stops but gives no coordinates. This script
searches the OpenStreetMap data inside the app's own offline map archive for
features whose name contains one of the search words for each stop, and
writes what it finds to tools/data/stop_candidates.json for a person to
review.

Nothing this script finds is official or goes into the app by itself: a
match only says that OpenStreetMap has something with a similar name there.

Run from the project root:

    tools/map/.venv/Scripts/python tools/data/find_stop_candidates.py
"""

from __future__ import annotations

import gzip
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "map"))

from inspect_basemap import ARCHIVE, decode_value, fields, packed_varints  # noqa: E402
from pmtiles.reader import MmapSource, Reader, all_tiles  # noqa: E402

OUTPUT = ROOT / "tools" / "data" / "stop_candidates.json"
UNIVERSITY = (22.659967, 90.363381)
ZOOM = 15

# Stop (Bangla, as published) -> words to look for in map names. Several
# spellings are tried because romanisation varies.
STOPS = {
    "বিশ্ববিদ্যালয়": ["University of Bari", "Barishal University", "Barisal University", "বরিশাল বিশ্ববিদ্যালয়"],
    "বরিশাল ক্লাব": ["Barishal Club", "Barisal Club", "বরিশাল ক্লাব"],
    "বাংলাবাজার মোড়": ["Bangla Bazar", "Banglabazar", "Bangla Bazaar", "বাংলাবাজার", "বাংলা বাজার"],
    "নুরিয়া স্কুল": ["Nuria", "Nooria", "Nuriya", "Nuriah", "নুরিয়া", "নূরিয়া"],
    "আমতলার মোড়": ["Amtala", "Amtola", "আমতলা"],
    "রুপাতলী হাউজিং": ["Rupatali", "Rupatoli", "Ruptali", "রুপাতলী", "রূপাতলী"],
    "কাঠালতলা": ["Kathaltala", "Kathaltola", "Kanthaltala", "Kathal", "কাঠালতলা", "কাঁঠালতলা"],
    "টোলঘর": ["Toll", "টোল"],
    "নতুন বাজার (টেম্পু স্ট্যান্ড)": ["Notun Bazar", "Natun Bazar", "Notun Bazaar", "Natun Bazaar", "New Market", "নতুন বাজার", "নতুনবাজার"],
    "মুন্সি গ্যারেজ": ["Munshi", "Munsi", "মুন্সি", "মুন্সী"],
    "অপসোনিন মোড়": ["Opsonin", "অপসোনিন"],
    "বটতলার মোড়": ["Bottola", "Battala", "Bottala", "Bot Tola", "Bottala", "বটতলা"],
    "করিমকুটির": ["Karim Kutir", "Karimkutir", "Korim Kutir", "Karim Kuthir", "করিম কুটির", "করিমকুটির"],
    "নথুল্লাবাদ ব্রীজের ঢাল": ["Nathullabad", "Nothullabad", "Natullabad", "Nathulabad", "নথুল্লাবাদ"],
    "কলেজ এভিনিউ": ["College Avenue", "College Ave", "কলেজ এভিনিউ"],
    "টিটিসি মূল গেট": ["TTC", "Technical Training", "টিটিসি", "কারিগরি প্রশিক্ষণ"],
    "চৌমাথা মোড়": ["Chowmatha", "Choumatha", "Chaumatha", "Chowmata", "Chowmuhani", "চৌমাথা"],
    "থানা কাউন্সিলের মূল গেট": ["Thana Council", "Upazila Parishad", "Upazilla Parishad", "থানা কাউন্সিল", "উপজেলা পরিষদ"],
    "ট্রাস্ট ভবন": ["Trust", "ট্রাস্ট"],
}


def zigzag(value: int) -> int:
    return (value >> 1) ^ -(value & 1)


def geometry_points(commands: list[int]) -> list[tuple[int, int]]:
    """Every vertex of a vector-tile geometry, in tile units."""
    points = []
    x = y = 0
    index = 0
    while index < len(commands):
        command = commands[index] & 7
        count = commands[index] >> 3
        index += 1
        if command in (1, 2):
            for _ in range(count):
                x += zigzag(commands[index])
                y += zigzag(commands[index + 1])
                index += 2
                points.append((x, y))
    return points


def layer_features(data: bytes):
    """Yields (layer name, geometry type, properties, points, extent)."""
    name = ""
    extent = 4096
    keys: list[str] = []
    values: list = []
    raw = []
    for number, _, value in fields(data):
        if number == 1:
            name = value.decode("utf-8")
        elif number == 2:
            geometry_type, tags, geometry = 0, [], []
            for f_number, _, f_value in fields(value):
                if f_number == 2:
                    tags = packed_varints(f_value)
                elif f_number == 3:
                    geometry_type = f_value
                elif f_number == 4:
                    geometry = packed_varints(f_value)
            raw.append((geometry_type, tags, geometry))
        elif number == 3:
            keys.append(value.decode("utf-8"))
        elif number == 4:
            values.append(decode_value(value))
        elif number == 5:
            extent = value
    for geometry_type, tags, geometry in raw:
        properties = {
            keys[tags[i]]: values[tags[i + 1]] for i in range(0, len(tags), 2)
        }
        yield name, geometry_type, properties, geometry_points(geometry), extent


def to_lat_lon(zoom: int, tile_x: int, tile_y: int, px: float, py: float, extent: int):
    n = 2**zoom
    lon = (tile_x + px / extent) / n * 360.0 - 180.0
    lat = math.degrees(
        math.atan(math.sinh(math.pi * (1 - 2 * (tile_y + py / extent) / n)))
    )
    return lat, lon


def distance_km(a, b) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    named = []
    with open(ARCHIVE, "rb") as handle:
        reader = Reader(MmapSource(handle))
        for (zoom, tile_x, tile_y), tile in all_tiles(reader.get_bytes):
            if zoom != ZOOM:
                continue
            for number, _, value in fields(gzip.decompress(tile)):
                if number != 3:
                    continue
                for layer, geometry_type, properties, points, extent in layer_features(value):
                    names = {
                        str(v)
                        for k, v in properties.items()
                        if k.startswith("name") and isinstance(v, str)
                    }
                    if not names or not points:
                        continue
                    # Keep only the part of the feature inside its own tile.
                    inside = [
                        p for p in points if 0 <= p[0] <= extent and 0 <= p[1] <= extent
                    ]
                    if not inside:
                        continue
                    px = sum(p[0] for p in inside) / len(inside)
                    py = sum(p[1] for p in inside) / len(inside)
                    lat, lon = to_lat_lon(zoom, tile_x, tile_y, px, py, extent)
                    named.append(
                        {
                            "names": sorted(names),
                            "layer": layer,
                            "kind": str(properties.get("kind", "")),
                            "shape": {1: "point", 2: "line", 3: "area"}.get(geometry_type, "?"),
                            "lat": round(lat, 6),
                            "lon": round(lon, 6),
                        }
                    )
    print(f"{len(named)} named features at zoom {ZOOM}")

    results = {}
    for stop, words in STOPS.items():
        lowered = [word.lower() for word in words]
        matches = {}
        for feature in named:
            text = " | ".join(feature["names"]).lower()
            if not any(word in text for word in lowered):
                continue
            # A road or area cut by tile edges appears once per tile: keep
            # the piece nearest the university for each distinct name.
            key = (tuple(feature["names"]), feature["layer"], feature["kind"])
            entry = dict(feature)
            entry["km_from_university"] = round(
                distance_km(UNIVERSITY, (feature["lat"], feature["lon"])), 2
            )
            pieces = matches.setdefault(key, [])
            pieces.append(entry)
        candidates = []
        for pieces in matches.values():
            pieces.sort(key=lambda e: e["km_from_university"])
            best = pieces[0]
            best["pieces"] = len(pieces)
            if len(pieces) > 1:
                best["lat_range"] = [min(p["lat"] for p in pieces), max(p["lat"] for p in pieces)]
                best["lon_range"] = [min(p["lon"] for p in pieces), max(p["lon"] for p in pieces)]
            candidates.append(best)
        candidates.sort(key=lambda e: e["km_from_university"])
        results[stop] = candidates
        print(f"\n{stop}  ({words[0]}): {len(candidates)} matches")
        for c in candidates[:14]:
            print(
                f"   {c['lat']:.5f}, {c['lon']:.5f}  {c['km_from_university']:5.2f} km  "
                f"{c['layer']}/{c['kind']} {c['shape']} x{c['pieces']}  {' | '.join(c['names'])}"
            )

    OUTPUT.write_text(
        json.dumps(
            {
                "note": "Name matches from the OpenStreetMap data in the app's "
                "offline map, for review. Not official, not confirmed, not "
                "used by the app.",
                "stops": results,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\nWrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
