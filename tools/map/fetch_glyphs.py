"""Downloads the glyph ranges the map styles need, for offline use.

MapLibre draws labels from signed-distance-field glyph files, one per font and
256-codepoint range. The styles reference them locally, so every range of
every font used must be in the app.

Source: Protomaps basemaps-assets (Noto Sans, SIL Open Font License 1.1).

Usage (from the project root):

    tools/map/.venv/Scripts/python tools/map/fetch_glyphs.py
"""

from __future__ import annotations

import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SOURCE = "https://protomaps.github.io/basemaps-assets/fonts/{font}/{range}.pbf"
USER_AGENT = "barishal-basemap-extract/1.0"

# Local folder name (no spaces, so it is safe in asset URLs on every platform)
# mapped to the font stack name on the source server.
FONTS = {
    "NotoSans-Regular": "Noto Sans Regular",
    "NotoSans-Medium": "Noto Sans Medium",
    "NotoSans-Italic": "Noto Sans Italic",
}

OUTPUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "map" / "fonts"


def fetch(job: tuple[str, str, int]) -> tuple[str, int, int | None]:
    local_name, source_name, start = job
    glyph_range = f"{start}-{start + 255}"
    target = OUTPUT_DIR / local_name / f"{glyph_range}.pbf"
    if target.exists():
        return local_name, start, target.stat().st_size
    url = SOURCE.format(font=urllib.parse.quote(source_name), range=glyph_range)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            target.write_bytes(data)
            return local_name, start, len(data)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return local_name, start, None
            time.sleep(1.5 * (attempt + 1))
        except Exception:  # noqa: BLE001 - retried
            time.sleep(1.5 * (attempt + 1))
    raise IOError(f"could not download {url}")


def main() -> int:
    jobs = []
    for local_name, source_name in FONTS.items():
        (OUTPUT_DIR / local_name).mkdir(parents=True, exist_ok=True)
        jobs += [(local_name, source_name, start) for start in range(0, 65536, 256)]

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(fetch, jobs))

    for local_name in FONTS:
        sizes = [size for name, _, size in results if name == local_name]
        present = [size for size in sizes if size is not None]
        missing = [
            start
            for name, start, size in results
            if name == local_name and size is None
        ]
        print(
            f"{local_name}: {len(present)} ranges, "
            f"{sum(present) / 1e6:.2f} MB, {len(missing)} not on server"
        )
        if missing:
            print(f"  missing ranges start at: {missing[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
