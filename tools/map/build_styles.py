"""Generates the app's light and dark MapLibre styles.

Both styles share one layer list and differ only in colour, so they cannot
drift apart. Edit the palettes or the layer list here, then run (from the
project root):

    python tools/map/build_styles.py

Output: assets/map_styles/light.json and assets/map_styles/dark.json.

The styles target the Protomaps basemap schema (layers: earth, water, landuse,
roads, buildings, boundaries, places, pois). `{{BASEMAP_URL}}` and
`{{GLYPHS_URL}}` are placeholders that the app replaces at run time with the
location of the local tile archive and glyph files. The styles use no sprite.
"""

from __future__ import annotations

import json
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "map_styles"
STYLE_VERSION = 1
SOURCE = "basemap"

REGULAR = ["NotoSans-Regular"]
MEDIUM = ["NotoSans-Medium"]
ITALIC = ["NotoSans-Italic"]

# English name when OpenStreetMap has one, otherwise the local name.
NAME = ["coalesce", ["get", "name:en"], ["get", "name"]]

PALETTES = {
    "light": {
        "land": "#f1f3f5",
        "water": "#b4d4ec",
        "water_line": "#b4d4ec",
        "park": "#d3e6c9",
        "wood": "#d8e7cf",
        "grass": "#e0ead5",
        "farmland": "#eef0ee",
        "wetland": "#dde8df",
        "residential": "#eceff2",
        "industrial": "#e6e9ed",
        "education": "#f3ebd9",
        "medical": "#f6e4e2",
        "sand": "#f1e8d2",
        "building": "#e2e6ea",
        "building_outline": "#d3d9df",
        "arterial": "#f6dfa0",
        "arterial_casing": "#dfc069",
        "major": "#ffffff",
        "major_casing": "#c9d0d7",
        "minor": "#ffffff",
        "minor_casing": "#d9dee4",
        "minor_thin": "#cfd5db",
        "path": "#c2c9d1",
        "ferry": "#7faed6",
        "aeroway": "#d9dee3",
        "rail": "#b5bdc6",
        "boundary": "#aab3bd",
        "halo": "#ffffff",
        "label_city": "#1d2733",
        "label_town": "#2c3743",
        "label_village": "#4a5663",
        "label_road": "#55616e",
        "label_water": "#3a78b0",
        "label_poi": "#4a5663",
        "poi_education": "#8a6d3b",
        "poi_medical": "#c6303a",
        "poi_transport": "#2c6cb3",
        "poi_green": "#3a8a58",
        "poi_civic": "#6f666b",
        "poi_commerce": "#b8682a",
    },
    "dark": {
        "land": "#151b22",
        "water": "#13293d",
        "water_line": "#183349",
        "park": "#152a24",
        "wood": "#14261f",
        "grass": "#172922",
        "farmland": "#161c20",
        "wetland": "#132527",
        "residential": "#171d24",
        "industrial": "#191f26",
        "education": "#1d2026",
        "medical": "#211c22",
        "sand": "#1f1f1e",
        "building": "#1e252e",
        "building_outline": "#28313b",
        "arterial": "#566170",
        "arterial_casing": "#262e38",
        "major": "#465160",
        "major_casing": "#222a33",
        "minor": "#343e4a",
        "minor_casing": "#1c232b",
        "minor_thin": "#303a45",
        "path": "#3c4652",
        "ferry": "#3a6288",
        "aeroway": "#222a33",
        "rail": "#414b57",
        "boundary": "#525d6a",
        "halo": "#151b22",
        "label_city": "#eef2f6",
        "label_town": "#d6dde4",
        "label_village": "#aeb8c2",
        "label_road": "#93a0ad",
        "label_water": "#6ea5dc",
        "label_poi": "#9aa6b2",
        "poi_education": "#d2a45e",
        "poi_medical": "#e08088",
        "poi_transport": "#72a9e8",
        "poi_green": "#5fbf8f",
        "poi_civic": "#9a939c",
        "poi_commerce": "#d9955c",
    },
}

ARTERIAL_DETAILS = [
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
]
MAJOR_DETAILS = ["secondary", "secondary_link", "tertiary", "tertiary_link"]
SERVICE_DETAILS = ["service", "track"]

POI_GROUPS = {
    "poi_education": ["university", "college", "school", "kindergarten", "library"],
    "poi_medical": ["hospital", "clinic", "doctors", "pharmacy"],
    "poi_transport": [
        "bus_station",
        "bus_stop",
        "ferry_terminal",
        "station",
        "aerodrome",
    ],
    "poi_green": [
        "park",
        "garden",
        "playground",
        "nature_reserve",
        "stadium",
        "pitch",
    ],
    "poi_civic": [
        "townhall",
        "police",
        "post_office",
        "fire_station",
        "courthouse",
        "place_of_worship",
        "museum",
    ],
    "poi_commerce": [
        "marketplace",
        "supermarket",
        "bank",
        "fuel",
        "restaurant",
        "cafe",
        "hotel",
        "hostel",
        "convenience",
        "mall",
    ],
}
# Shown from zoom 13: the places people navigate by.
POI_PROMINENT = [
    "university",
    "college",
    "hospital",
    "bus_station",
    "ferry_terminal",
    "aerodrome",
    "stadium",
    "marketplace",
    "townhall",
    "park",
]
POI_ALL = [kind for kinds in POI_GROUPS.values() for kind in kinds]


def kind_in(values: list[str], key: str = "kind") -> list:
    return ["in", ["get", key], ["literal", values]]


def zoom_width(*stops: float) -> list:
    """Line width that grows smoothly with zoom: zoom, width, zoom, width..."""
    return ["interpolate", ["exponential", 1.6], ["zoom"], *stops]


def poi_color(palette: dict) -> list:
    expression: list = ["match", ["get", "kind"]]
    for group, kinds in POI_GROUPS.items():
        expression += [kinds, palette[group]]
    expression.append(palette["label_poi"])
    return expression


def road_filter(kind_filter: list) -> list:
    return ["all", ["==", ["geometry-type"], "LineString"], kind_filter]


ARTERIAL = [
    "any",
    ["==", ["get", "kind"], "highway"],
    kind_in(ARTERIAL_DETAILS, "kind_detail"),
]
MAJOR = kind_in(MAJOR_DETAILS, "kind_detail")
MINOR = [
    "all",
    ["==", ["get", "kind"], "minor_road"],
    ["!", kind_in(SERVICE_DETAILS, "kind_detail")],
]
SERVICE = [
    "all",
    kind_in(["minor_road", "path", "other"]),
    kind_in(SERVICE_DETAILS, "kind_detail"),
]
PATH = [
    "all",
    ["==", ["get", "kind"], "path"],
    ["!", kind_in(SERVICE_DETAILS, "kind_detail")],
]

ARTERIAL_WIDTH = (8, 0.9, 10, 1.6, 12, 2.6, 14, 5, 16, 12, 18, 30)
MAJOR_WIDTH = (10, 0.7, 12, 1.5, 14, 3.4, 16, 9, 18, 24)
MINOR_WIDTH = (12, 0.4, 14, 1.5, 16, 6, 18, 18)
SERVICE_WIDTH = (14, 0.6, 16, 2.6, 18, 9)


def cased(width: tuple, extra: float) -> list:
    stops = list(width)
    for index in range(1, len(stops), 2):
        stops[index] = round(stops[index] + extra, 2)
    return zoom_width(*stops)


def line(layer_id: str, source_layer: str, layer_filter: list, paint: dict, **extra):
    return {
        "id": layer_id,
        "type": "line",
        "source": SOURCE,
        "source-layer": source_layer,
        "filter": layer_filter,
        "layout": {"line-cap": "round", "line-join": "round"},
        "paint": paint,
        **extra,
    }


def fill(layer_id: str, source_layer: str, layer_filter: list, color: str, **extra):
    return {
        "id": layer_id,
        "type": "fill",
        "source": SOURCE,
        "source-layer": source_layer,
        "filter": layer_filter,
        "paint": {"fill-color": color},
        **extra,
    }


def label(
    layer_id: str,
    source_layer: str,
    layer_filter: list,
    *,
    font: list,
    size,
    color: str,
    halo: str,
    layout: dict | None = None,
    paint: dict | None = None,
    **extra,
):
    return {
        "id": layer_id,
        "type": "symbol",
        "source": SOURCE,
        "source-layer": source_layer,
        "filter": layer_filter,
        "layout": {
            "text-field": NAME,
            "text-font": font,
            "text-size": size,
            "text-max-width": 8,
            **(layout or {}),
        },
        "paint": {
            "text-color": color,
            "text-halo-color": halo,
            "text-halo-width": 1.4,
            **(paint or {}),
        },
        **extra,
    }


def landuse(layer_id: str, kinds: list[str], color: str, **extra):
    return fill(layer_id, "landuse", kind_in(kinds), color, **extra)


def layers(p: dict) -> list[dict]:
    polygon = ["==", ["geometry-type"], "Polygon"]
    line_string = ["==", ["geometry-type"], "LineString"]
    point = ["==", ["geometry-type"], "Point"]

    return [
        {"id": "background", "type": "background", "paint": {"background-color": p["land"]}},
        # --- Land use ---------------------------------------------------
        landuse("landuse-residential", ["residential"], p["residential"]),
        landuse("landuse-farmland", ["farmland", "meadow"], p["farmland"]),
        landuse(
            "landuse-industrial",
            ["industrial", "commercial", "military", "aerodrome", "pier"],
            p["industrial"],
        ),
        landuse(
            "landuse-education",
            ["university", "college", "school", "kindergarten"],
            p["education"],
        ),
        landuse("landuse-medical", ["hospital"], p["medical"]),
        landuse("landuse-sand", ["sand", "bare_rock"], p["sand"]),
        landuse("landuse-wetland", ["wetland"], p["wetland"]),
        landuse("landuse-grass", ["grassland", "grass", "scrub"], p["grass"]),
        landuse("landuse-wood", ["wood", "forest"], p["wood"]),
        landuse(
            "landuse-park",
            [
                "park",
                "garden",
                "playground",
                "pitch",
                "recreation_ground",
                "nature_reserve",
            ],
            p["park"],
        ),
        # --- Water ------------------------------------------------------
        fill("water", "water", polygon, p["water"]),
        line(
            "waterway",
            "water",
            ["all", line_string, kind_in(["river", "canal"])],
            {
                "line-color": p["water_line"],
                "line-width": zoom_width(10, 0.6, 13, 1.4, 15, 3, 18, 8),
            },
        ),
        line(
            "waterway-small",
            "water",
            ["all", line_string, kind_in(["stream", "ditch", "drain"])],
            {
                "line-color": p["water_line"],
                "line-width": zoom_width(13, 0.5, 16, 1.6, 18, 4),
            },
            minzoom=13,
        ),
        # --- Buildings --------------------------------------------------
        {
            "id": "building",
            "type": "fill",
            "source": SOURCE,
            "source-layer": "buildings",
            "filter": ["all", polygon, ["==", ["get", "kind"], "building"]],
            "minzoom": 14,
            "maxzoom": 16,
            "paint": {
                "fill-color": p["building"],
                "fill-outline-color": p["building_outline"],
                "fill-opacity": ["interpolate", ["linear"], ["zoom"], 14, 0, 14.6, 1],
            },
        },
        # --- Roads ------------------------------------------------------
        line(
            "road-aeroway",
            "roads",
            road_filter(["==", ["get", "kind"], "aeroway"]),
            {
                "line-color": p["aeroway"],
                "line-width": zoom_width(11, 1, 14, 6, 16, 24),
            },
            minzoom=11,
        ),
        line(
            "road-path",
            "roads",
            road_filter(PATH),
            {
                "line-color": p["path"],
                "line-width": zoom_width(15, 0.8, 18, 2.6),
                "line-dasharray": [2, 1.5],
            },
            minzoom=15,
        ),
        line(
            "road-service-casing",
            "roads",
            road_filter(SERVICE),
            {"line-color": p["minor_casing"], "line-width": cased(SERVICE_WIDTH, 1.2)},
            minzoom=15,
        ),
        line(
            "road-minor-casing",
            "roads",
            road_filter(MINOR),
            {"line-color": p["minor_casing"], "line-width": cased(MINOR_WIDTH, 1.4)},
            minzoom=14,
        ),
        line(
            "road-major-casing",
            "roads",
            road_filter(MAJOR),
            {"line-color": p["major_casing"], "line-width": cased(MAJOR_WIDTH, 1.6)},
            minzoom=11,
        ),
        line(
            "road-arterial-casing",
            "roads",
            road_filter(ARTERIAL),
            {
                "line-color": p["arterial_casing"],
                "line-width": cased(ARTERIAL_WIDTH, 1.8),
            },
            minzoom=10,
        ),
        line(
            "road-service",
            "roads",
            road_filter(SERVICE),
            {"line-color": p["minor"], "line-width": zoom_width(*SERVICE_WIDTH)},
            minzoom=14,
        ),
        line(
            "road-minor",
            "roads",
            road_filter(MINOR),
            {
                # A thin grey line when zoomed out, a white street when close.
                "line-color": [
                    "interpolate",
                    ["linear"],
                    ["zoom"],
                    13.5,
                    p["minor_thin"],
                    14.5,
                    p["minor"],
                ],
                "line-width": zoom_width(*MINOR_WIDTH),
            },
            minzoom=12,
        ),
        line(
            "road-major",
            "roads",
            road_filter(MAJOR),
            {"line-color": p["major"], "line-width": zoom_width(*MAJOR_WIDTH)},
            minzoom=10,
        ),
        line(
            "road-arterial",
            "roads",
            road_filter(ARTERIAL),
            {"line-color": p["arterial"], "line-width": zoom_width(*ARTERIAL_WIDTH)},
        ),
        line(
            "rail",
            "roads",
            road_filter(["==", ["get", "kind"], "rail"]),
            {
                "line-color": p["rail"],
                "line-width": zoom_width(10, 0.8, 14, 1.6, 18, 4),
            },
        ),
        line(
            "ferry",
            "roads",
            road_filter(["==", ["get", "kind"], "ferry"]),
            {
                "line-color": p["ferry"],
                "line-width": zoom_width(10, 0.8, 14, 1.4, 18, 2.4),
                "line-dasharray": [3, 3],
                "line-opacity": 0.6,
            },
            minzoom=11,
        ),
        # --- 3D buildings (seen when the map is tilted) -----------------
        {
            "id": "building-3d",
            "type": "fill-extrusion",
            "source": SOURCE,
            "source-layer": "buildings",
            "filter": ["all", polygon, ["==", ["get", "kind"], "building"]],
            "minzoom": 15,
            "paint": {
                "fill-extrusion-color": p["building"],
                "fill-extrusion-height": ["coalesce", ["get", "height"], 5],
                "fill-extrusion-base": 0,
                "fill-extrusion-opacity": 0.92,
            },
        },
        # --- Boundaries -------------------------------------------------
        line(
            "boundary",
            "boundaries",
            kind_in(["country", "region"]),
            {
                "line-color": p["boundary"],
                "line-width": 1,
                "line-dasharray": [4, 3],
            },
        ),
        # --- Labels (later layers win when labels collide) --------------
        label(
            "label-water-line",
            "water",
            ["all", line_string, kind_in(["river", "canal"]), ["has", "name"]],
            font=ITALIC,
            size=["interpolate", ["linear"], ["zoom"], 12, 11, 16, 13],
            color=p["label_water"],
            halo=p["halo"],
            layout={"symbol-placement": "line", "symbol-spacing": 320},
            minzoom=12,
        ),
        label(
            "label-road-minor",
            "roads",
            ["all", line_string, ["has", "name"], ["any", MINOR, SERVICE]],
            font=REGULAR,
            size=["interpolate", ["linear"], ["zoom"], 15, 10.5, 18, 13],
            color=p["label_road"],
            halo=p["halo"],
            layout={"symbol-placement": "line", "symbol-spacing": 280},
            minzoom=15,
        ),
        label(
            "label-road-major",
            "roads",
            ["all", line_string, ["has", "name"], ["any", ARTERIAL, MAJOR]],
            font=REGULAR,
            size=["interpolate", ["linear"], ["zoom"], 12, 10.5, 16, 12.5, 18, 14],
            color=p["label_road"],
            halo=p["halo"],
            layout={"symbol-placement": "line", "symbol-spacing": 360},
            minzoom=12,
        ),
        {
            "id": "poi-dot",
            "type": "circle",
            "source": SOURCE,
            "source-layer": "pois",
            "filter": ["all", kind_in(POI_ALL), ["has", "name"]],
            "minzoom": 15.5,
            "paint": {
                "circle-radius": ["interpolate", ["linear"], ["zoom"], 15.5, 2.5, 18, 4],
                "circle-color": poi_color(p),
                "circle-stroke-color": p["halo"],
                "circle-stroke-width": 1,
            },
        },
        label(
            "label-poi",
            "pois",
            ["all", kind_in(POI_ALL), ["has", "name"]],
            font=REGULAR,
            size=["interpolate", ["linear"], ["zoom"], 15.5, 10.5, 18, 12.5],
            color=poi_color(p),
            halo=p["halo"],
            layout={
                "text-anchor": "top",
                "text-offset": [0, 0.5],
                "symbol-sort-key": ["get", "min_zoom"],
            },
            minzoom=15.5,
        ),
        label(
            "label-poi-prominent",
            "pois",
            ["all", kind_in(POI_PROMINENT), ["has", "name"]],
            font=MEDIUM,
            size=["interpolate", ["linear"], ["zoom"], 13, 10.5, 16, 12.5],
            color=poi_color(p),
            halo=p["halo"],
            layout={"symbol-sort-key": ["get", "min_zoom"]},
            minzoom=13,
            maxzoom=15.5,
        ),
        label(
            "label-water-point",
            "water",
            ["all", point, ["has", "name"]],
            font=ITALIC,
            size=["interpolate", ["linear"], ["zoom"], 10, 11, 16, 14],
            color=p["label_water"],
            halo=p["halo"],
            layout={"text-letter-spacing": 0.05},
        ),
        label(
            "label-place-village",
            "places",
            kind_in(["village", "hamlet", "locality", "neighbourhood"], "kind_detail"),
            font=REGULAR,
            size=["interpolate", ["linear"], ["zoom"], 11, 10.5, 15, 13],
            color=p["label_village"],
            halo=p["halo"],
            layout={"symbol-sort-key": ["get", "min_zoom"]},
            minzoom=11.5,
        ),
        label(
            "label-place-town",
            "places",
            kind_in(["town"], "kind_detail"),
            font=MEDIUM,
            size=["interpolate", ["linear"], ["zoom"], 9, 11, 14, 15],
            color=p["label_town"],
            halo=p["halo"],
            layout={"symbol-sort-key": ["get", "min_zoom"]},
            minzoom=9,
        ),
        label(
            "label-place-city",
            "places",
            kind_in(["city"], "kind_detail"),
            font=MEDIUM,
            size=["interpolate", ["linear"], ["zoom"], 8, 13, 14, 20],
            color=p["label_city"],
            halo=p["halo"],
            paint={"text-halo-width": 1.8},
        ),
    ]


def build(theme: str) -> dict:
    palette = PALETTES[theme]
    return {
        "version": 8,
        "name": f"University of Barishal {theme}",
        "metadata": {"bu:theme": theme, "bu:styleVersion": STYLE_VERSION},
        "glyphs": "{{GLYPHS_URL}}",
        "sources": {
            SOURCE: {
                "type": "vector",
                "url": "{{BASEMAP_URL}}",
                "attribution": "© OpenStreetMap contributors, Protomaps",
            }
        },
        "layers": layers(palette),
    }


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for theme in PALETTES:
        path = OUTPUT_DIR / f"{theme}.json"
        path.write_text(
            json.dumps(build(theme), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {path} ({len(layers(PALETTES[theme]))} layers)")


if __name__ == "__main__":
    main()
