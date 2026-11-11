"""Writes assets/review/stops.geojson: stop positions awaiting confirmation.

The official schedule names its stops but gives no positions. The positions
below were found by searching OpenStreetMap for each name
(tools/data/find_stop_candidates.py) and picking the closest-sounding match.
THEY ARE NOT CONFIRMED. Each is a landmark with a similar name, not a known
boarding point.

The app loads this file only when built with
`--dart-define=REVIEW_STOPS=true`, and then labels everything "Unconfirmed
stop positions". Its purpose is to let someone who knows the city check each
position on the map.

When a position is confirmed or corrected, move the stop to
assets/data/stops.geojson (see docs/TRANSPORT_DATA_FORMAT.md) and delete it
from here.

Run from the project root:  python tools/data/build_review_stops.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
FOLDER = ROOT / "assets" / "review"

# (id, English name, official Bangla name, latitude, longitude,
#  what was matched in OpenStreetMap, routes that list the stop)
CANDIDATES = [
    ("university", "University", "বিশ্ববিদ্যালয়", 22.659967, 90.363381,
     'Matched to "University of Barisal".', "01, 02, 03"),
    ("kathaltola", "Kathaltola", "কাঠালতলা", 22.67428, 90.34692,
     'Matched to "kathaltola bus stop".', "01, 03"),
    ("rupatoli-housing", "Rupatoli Housing", "রুপাতলী হাউজিং", 22.67749, 90.34904,
     'Matched to "Rupatoli Housing Estate", the estate and not a point on the road.',
     "01, 03"),
    ("amtala-mor", "Amtala Mor", "আমতলার মোড়", 22.68884, 90.35616,
     'Only "Amtola Lake" was found, which is near the junction, not on it.',
     "01, 03"),
    ("nuria-school", "Nuria School", "নুরিয়া স্কুল", 22.69026, 90.35940,
     'Matched to "Nuria Ideal School".', "01"),
    ("bangla-bazar-mor", "Bangla Bazar Mor", "বাংলাবাজার মোড়", 22.69280, 90.36245,
     'Matched to "Bangla Bazaar", the market and not the junction.', "01"),
    ("thana-council", "Thana Council Main Gate", "থানা কাউন্সিলের মূল গেট",
     22.69566, 90.35214, 'Matched to "Barisal Thana Council".', "03"),
    ("chowmatha-mor", "Chowmatha Mor", "চৌমাথা মোড়", 22.70051, 90.35383,
     'Matched to "Choumatha Bazar".', "03"),
    ("ttc-main-gate", "TTC Main Gate", "টিটিসি মূল গেট", 22.70453, 90.35368,
     'Matched to "Barisal Technical Training Center", not its gate.', "03"),
    ("nathullabad", "Nathullabad Bridge Slope", "নথুল্লাবাদ ব্রীজের ঢাল",
     22.71442, 90.34757,
     'Only the mosque at Nathullabad bus terminal was found, not the bridge slope.',
     "03"),
    ("bottola-mor", "Bottola Mor", "বটতলার মোড়", 22.70166, 90.36394,
     'Matched to "Bottola Bazar".', "02"),
    ("notun-bazar", "Notun Bazar (Tempo Stand)", "নতুন বাজার (টেম্পু স্ট্যান্ড)",
     22.71140, 90.36129, 'Matched to "Notun Bazaar".', "02"),
    ("opsonin-mor", "Opsonin Mor", "অপসোনিন মোড়", 22.65639, 90.34175,
     'DOUBTFUL: the only match is the Opsonin factory, which is probably the '
     "wrong place.", "02"),
]


def main() -> None:
    features = []
    for stop_id, english, bangla, latitude, longitude, matched, routes in CANDIDATES:
        features.append(
            {
                "type": "Feature",
                "properties": {
                    "id": f"review-{stop_id}",
                    "name": english,
                    "description": f"{bangla} · Route {routes}. {matched} "
                    "Position not confirmed.",
                },
                "geometry": {"type": "Point", "coordinates": [longitude, latitude]},
            }
        )

    note = (
        "UNCONFIRMED stop positions for review only. Found by name in "
        "OpenStreetMap, not confirmed by anyone. Loaded only with "
        "--dart-define=REVIEW_STOPS=true."
    )
    FOLDER.mkdir(parents=True, exist_ok=True)
    (FOLDER / "stops.geojson").write_text(
        json.dumps(
            {"type": "FeatureCollection", "unconfirmed": True, "note": note,
             "features": features},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    # No route lines: the roads each route follows are not known.
    (FOLDER / "routes.geojson").write_text(
        json.dumps(
            {"type": "FeatureCollection", "unconfirmed": True, "note": note,
             "features": []},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(features)} unconfirmed stops to assets/review/")


if __name__ == "__main__":
    main()
