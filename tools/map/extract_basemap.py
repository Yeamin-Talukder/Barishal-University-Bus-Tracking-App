"""Builds the app's offline basemap archive.

Copies the vector tiles that cover the University of Barishal area out of a
Protomaps daily planet build (OpenStreetMap data, ODbL) into one small PMTiles
file. Only the needed byte ranges are downloaded, a few megabytes in total.

Usage (from the project root):

    tools/map/.venv/Scripts/python tools/map/extract_basemap.py

The coverage constants below must match `UniversityMapConfiguration` in
`lib/core/constants/university_map_configuration.dart`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from pmtiles.tile import (
    deserialize_directory,
    deserialize_header,
    find_tile,
    zxy_to_tileid,
)
from pmtiles.writer import write

CENTER_LATITUDE = 22.659967
CENTER_LONGITUDE = 90.363381
METERS_PER_DEGREE_LATITUDE = 111320.0

# The covered area follows the bus routes: every map tile within
# ROUTE_BUFFER_METERS of a route is kept, so the surroundings are the same
# width all the way along, like a band of small cells laid over the roads
# (map tiles are square, so the cells are squares rather than hexagons).
# The rectangle is the band's outline, and is where the camera may go.
# Until version 2 the package covered a 15 km circle, and in version 3 a
# plain rectangle; both were cut down at the owner's request.
ROUTE_BUFFER_METERS = 1500.0
COVERAGE_SOUTH = 22.643
COVERAGE_WEST = 90.331
COVERAGE_NORTH = 22.727
COVERAGE_EAST = 90.385

# The band is used from this zoom up, where nearly all the bytes are. Below
# it a tile is larger than the band, so the whole rectangle is kept.
BAND_FROM_ZOOM = 13

# The app shows zoom 10 to 18. Zoom 8 and 9 are included as a margin; zoom 15
# is the deepest the source has, and MapLibre overzooms it for 16 to 18.
MIN_ZOOM = 8
MAX_ZOOM = 15

# Extra tiles are stored around the covered rectangle so the map does not end
# in a straight line when the camera sits at its edge. The margin is half a
# large screen (in logical pixels) at each zoom, capped so the low zooms stay
# small.
EDGE_MARGIN_PIXELS = 250
MAX_EDGE_MARGIN_METERS = 20000.0
EARTH_CIRCUMFERENCE_METERS = 40075016.686

BUILDS_INDEX_URL = "https://build-metadata.protomaps.dev/builds.json"
BUILD_URL = "https://build.protomaps.com/{key}"
USER_AGENT = "barishal-basemap-extract/1.0"

PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = PROJECT_ROOT / "assets" / "map"
PACKAGE_VERSION = 4
ARCHIVE_NAME = f"barishal_basemap_v{PACKAGE_VERSION}.pmtiles"
MANIFEST_NAME = f"barishal_basemap_v{PACKAGE_VERSION}.json"


def coverage_bounds() -> tuple[float, float, float, float]:
    """South, west, north, east of the covered rectangle."""
    return COVERAGE_SOUTH, COVERAGE_WEST, COVERAGE_NORTH, COVERAGE_EAST


def tile_xy(latitude: float, longitude: float, zoom: int) -> tuple[int, int]:
    n = 2**zoom
    x = int((longitude + 180.0) / 360.0 * n)
    y = int(
        (1.0 - math.asinh(math.tan(math.radians(latitude))) / math.pi) / 2.0 * n
    )
    return x, y


def edge_margin_meters(zoom: int) -> float:
    """How far past the covered rectangle tiles are stored at [zoom]."""
    meters_per_pixel = (
        EARTH_CIRCUMFERENCE_METERS
        * math.cos(math.radians(CENTER_LATITUDE))
        / (512 * 2**zoom)
    )
    return min(EDGE_MARGIN_PIXELS * meters_per_pixel, MAX_EDGE_MARGIN_METERS)


def tiles_in_bounds(zoom: int, margin_meters: float = 0.0) -> list[tuple[int, int, int]]:
    south, west, north, east = coverage_bounds()
    latitude_margin = margin_meters / METERS_PER_DEGREE_LATITUDE
    longitude_margin = latitude_margin / math.cos(math.radians(CENTER_LATITUDE))
    x_min, y_min = tile_xy(north + latitude_margin, west - longitude_margin, zoom)
    x_max, y_max = tile_xy(south - latitude_margin, east + longitude_margin, zoom)
    return [
        (zoom, x, y)
        for x in range(x_min, x_max + 1)
        for y in range(y_min, y_max + 1)
    ]


def route_points() -> list[tuple[float, float]]:
    """Points along every route, no more than about 40 m apart."""
    draft = json.loads(
        (PROJECT_ROOT / "tools" / "data" / "routes_draft.json").read_text("utf-8")
    )
    points: list[tuple[float, float]] = []
    for route in draft["routes"].values():
        path = route["path"]
        for (lat1, lon1), (lat2, lon2) in zip(path, path[1:]):
            meters = math.hypot(
                (lat2 - lat1) * METERS_PER_DEGREE_LATITUDE,
                (lon2 - lon1)
                * METERS_PER_DEGREE_LATITUDE
                * math.cos(math.radians(lat1)),
            )
            steps = max(1, int(meters // 40))
            for step in range(steps):
                f = step / steps
                points.append((lat1 + (lat2 - lat1) * f, lon1 + (lon2 - lon1) * f))
        points.append(tuple(path[-1]))
    return points


def tile_bounds(zoom: int, x: int, y: int) -> tuple[float, float, float, float]:
    n = 2**zoom

    def latitude(row: int) -> float:
        return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * row / n))))

    return latitude(y + 1), x / n * 360 - 180, latitude(y), (x + 1) / n * 360 - 180


def tiles_near_routes(
    zoom: int, points: list[tuple[float, float]], reach_meters: float
) -> list[tuple[int, int, int]]:
    """The tiles of the rectangle that come within reach of a route."""
    kept = []
    for z, x, y in tiles_in_bounds(zoom, reach_meters):
        south, west, north, east = tile_bounds(z, x, y)
        for latitude, longitude in points:
            # Distance from the point to the tile's rectangle.
            d_lat = max(south - latitude, 0.0, latitude - north)
            d_lon = max(west - longitude, 0.0, longitude - east)
            meters = math.hypot(
                d_lat * METERS_PER_DEGREE_LATITUDE,
                d_lon * METERS_PER_DEGREE_LATITUDE * math.cos(math.radians(latitude)),
            )
            if meters <= reach_meters:
                kept.append((z, x, y))
                break
    return kept


def coverage_tiles(zoom: int, points, margin_meters: float = 0.0):
    if zoom < BAND_FROM_ZOOM:
        return tiles_in_bounds(zoom, margin_meters)
    return tiles_near_routes(zoom, points, ROUTE_BUFFER_METERS + margin_meters)


def fetch_range(url: str, offset: int, length: int) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "Range": f"bytes={offset}-{offset + length - 1}",
            "User-Agent": USER_AGENT,
        },
    )
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            if len(data) != length:
                raise IOError(f"expected {length} bytes, got {len(data)}")
            return data
        except Exception as error:  # noqa: BLE001 - retried, then re-raised
            last_error = error
            time.sleep(1.5 * (attempt + 1))
    raise IOError(f"range {offset}+{length} failed: {last_error}")


def latest_build_key() -> str:
    request = urllib.request.Request(
        BUILDS_INDEX_URL, headers={"User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        builds = json.load(response)
    return sorted(build["key"] for build in builds)[-1]


class RemoteArchive:
    """Reads the header, directories and tiles of a remote PMTiles archive."""

    def __init__(self, url: str) -> None:
        self.url = url
        self.header = deserialize_header(fetch_range(url, 0, 127))
        self._root = deserialize_directory(
            fetch_range(url, self.header["root_offset"], self.header["root_length"])
        )
        self._leaves: dict[int, list] = {}

    def metadata(self) -> dict:
        import gzip

        raw = fetch_range(
            self.url, self.header["metadata_offset"], self.header["metadata_length"]
        )
        return json.loads(gzip.decompress(raw))

    def locate(self, tile_id: int) -> tuple[int, int] | None:
        """Absolute offset and length of a tile, or None if it is absent."""
        directory = self._root
        for _ in range(4):
            entry = find_tile(directory, tile_id)
            if entry is None:
                return None
            if entry.run_length > 0:
                return self.header["tile_data_offset"] + entry.offset, entry.length
            if entry.offset not in self._leaves:
                self._leaves[entry.offset] = deserialize_directory(
                    fetch_range(
                        self.url,
                        self.header["leaf_directory_offset"] + entry.offset,
                        entry.length,
                    )
                )
            directory = self._leaves[entry.offset]
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--build",
        help="Protomaps build key, e.g. 20261110.pmtiles (default: latest)",
    )
    args = parser.parse_args()

    build_key = args.build or latest_build_key()
    url = BUILD_URL.format(key=build_key)
    print(f"Source build: {url}")

    archive = RemoteArchive(url)
    source_metadata = archive.metadata()

    points = route_points()
    wanted = [
        (zxy_to_tileid(z, x, y), (z, x, y))
        for zoom in range(MIN_ZOOM, MAX_ZOOM + 1)
        for (z, x, y) in coverage_tiles(zoom, points, edge_margin_meters(zoom))
    ]
    wanted.sort()
    # The tiles the coverage itself needs, without the margin.
    required = {
        zxy
        for zoom in range(MIN_ZOOM, MAX_ZOOM + 1)
        for zxy in coverage_tiles(zoom, points)
    }

    located: list[tuple[int, tuple[int, int, int], tuple[int, int]]] = []
    missing: list[tuple[int, int, int]] = []
    for tile_id, zxy in wanted:
        location = archive.locate(tile_id)
        if location is None:
            missing.append(zxy)
        else:
            located.append((tile_id, zxy, location))
    print(f"Tiles wanted: {len(wanted)}, found: {len(located)}, absent: {len(missing)}")
    if missing:
        print(f"Absent tiles (no data in source): {missing[:10]}")
    missing_required = [zxy for zxy in missing if zxy in required]
    if missing_required:
        print(f"ERROR: tiles inside the coverage are absent: {missing_required[:10]}")
        return 1

    unique_ranges = sorted({location for _, _, location in located})
    print(f"Downloading {len(unique_ranges)} tile blobs...")
    with ThreadPoolExecutor(max_workers=8) as pool:
        blobs = dict(
            zip(
                unique_ranges,
                pool.map(lambda r: fetch_range(url, r[0], r[1]), unique_ranges),
            )
        )

    south, west, north, east = coverage_bounds()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    archive_path = OUTPUT_DIR / ARCHIVE_NAME

    per_zoom: dict[int, int] = {}
    with write(str(archive_path)) as writer:
        for tile_id, (z, _, _), location in located:
            writer.write_tile(tile_id, blobs[location])
            per_zoom[z] = per_zoom.get(z, 0) + 1
        writer.finalize(
            {
                "tile_type": archive.header["tile_type"],
                "tile_compression": archive.header["tile_compression"],
                "min_lon_e7": int(west * 1e7),
                "min_lat_e7": int(south * 1e7),
                "max_lon_e7": int(east * 1e7),
                "max_lat_e7": int(north * 1e7),
                "center_zoom": 14,
                "center_lon_e7": int(CENTER_LONGITUDE * 1e7),
                "center_lat_e7": int(CENTER_LATITUDE * 1e7),
            },
            {
                **source_metadata,
                "name": "University of Barishal offline basemap",
                "description": (
                    "The University of Barishal bus routes, extracted from "
                    f"Protomaps build {build_key}"
                ),
            },
        )

    data = archive_path.read_bytes()
    manifest = {
        "file": ARCHIVE_NAME,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "sourceBuild": build_key,
        "schemaVersion": source_metadata.get("version"),
        "minZoom": MIN_ZOOM,
        "maxZoom": MAX_ZOOM,
        "tileCount": len(located),
        "tilesPerZoom": {str(z): per_zoom[z] for z in sorted(per_zoom)},
        "coverageTilesPerZoom": {
            str(zoom): len(coverage_tiles(zoom, points))
            for zoom in range(MIN_ZOOM, MAX_ZOOM + 1)
        },
        "edgeMarginPixels": EDGE_MARGIN_PIXELS,
        "routeBufferMeters": ROUTE_BUFFER_METERS,
        "bounds": {"south": south, "west": west, "north": north, "east": east},
        "center": {"latitude": CENTER_LATITUDE, "longitude": CENTER_LONGITUDE},
        "attribution": "© OpenStreetMap contributors, Protomaps",
    }
    (OUTPUT_DIR / MANIFEST_NAME).write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    print(f"Wrote {archive_path} ({len(data) / 1e6:.2f} MB)")
    print(f"Tiles per zoom: {manifest['tilesPerZoom']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
