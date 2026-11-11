"""Works out the road path of each official route from its stops.

The official schedule lists each route's stops in order. An admin placed the
stops on the map in the app. This script reads those stops from the live
project (they are public), asks a road-routing service (OSRM, on
OpenStreetMap roads) for the way a vehicle drives through them in order, and
writes the result to tools/data/routes_draft.json for review.

What is and is not known:

  - The stops and their order are the transport office's.
  - The path between two stops is the routing service's choice of roads.
    It is the likely path, not a recorded one: where two roads join the same
    stops, the bus may use the other. Each route must be looked at on the
    map by someone who knows it.

Run from the project root:  python tools/data/build_routes.py
"""

import json
import math
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "tools" / "data" / "routes_draft.json"
PROJECT = "bus-tracker-162c0"
STOPS_URL = (
    "https://firestore.googleapis.com/v1/projects/"
    f"{PROJECT}/databases/(default)/documents/stops?pageSize=300"
)
OSRM = "https://router.project-osrm.org/route/v1/driving/"

# Route number -> name, colour, and its stops in order, each given as the
# name the admin saved the stop under. The schedule's own stop names are in
# assets/data/schedule.json; where the admin's name differs, the pairing was
# made by position and is noted.
ROUTES = {
    "01": {
        "name": "Route 01",
        "color": "#F2994A",
        "stops": [
            "Barishal Club",
            "Bangla Bazar Mor",
            "Nooria School",  # schedule: Nuria School
            "Amtolar Mor(barishal club bus)",  # schedule: Amtala Mor
            "Rupatoli",  # schedule: Rupatoli Housing
            "Kathaltola",
            "Toll Plaza",  # schedule: Toll Ghar
            "University (1st Gate)",  # schedule: University
        ],
    },
    "02": {
        "name": "Route 02",
        "color": "#6FA8FF",
        "stops": [
            "Notun Bazar (Tempo Stand)",
            "Munsi Garaz",  # schedule: Munshi Garage
            "Opsonin Mor",
            "Bottola Mor",
            "করিমকুটির",  # schedule: Karim Kutir
            # Not listed in the schedule for this route. The owner said
            # (11 November 2026) that from Chowmatha to the university the
            # bus runs and stops as the other routes do.
            "Chowmatha Mor",
            "Thana Council Main Gate",
            "Amtala Mor(RHD GATE)",
            "Rupatoli",
            "Kathaltola",
            "Toll Plaza",
            "University (1st Gate)",
        ],
    },
    "03": {
        "name": "Route 03",
        "color": "#B79CFF",
        "stops": [
            "Nathullabad Bridge Slope",
            "কলেজ এভিনিউ",  # schedule: College Avenue
            "TTC Main Gate",
            "Chowmatha Mor",
            "Thana Council Main Gate",
            "Amtala Mor(RHD GATE)",  # schedule: Amtala Mor
            "Rupatoli",
            "Kathaltola",
            "Toll Plaza",
            "University (1st Gate)",
        ],
    },
}


def fetch(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "route-path-builder/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def distance_m(a, b) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 6371008.8 * 2 * math.asin(math.sqrt(h))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    stops = {}
    for document in fetch(STOPS_URL).get("documents", []):
        fields = document["fields"]
        stops[fields["name"]["stringValue"]] = {
            "id": document["name"].split("/")[-1],
            "lat": float(fields["latitude"].get("doubleValue", fields["latitude"].get("integerValue"))),
            "lon": float(fields["longitude"].get("doubleValue", fields["longitude"].get("integerValue"))),
        }
    print(f"{len(stops)} stops read from the live project")

    used = set()
    result = {}
    for number, route in ROUTES.items():
        missing = [name for name in route["stops"] if name not in stops]
        if missing:
            raise SystemExit(f"Route {number}: no stop named {missing}")
        points = [stops[name] for name in route["stops"]]
        used.update(route["stops"])
        # Each leg is routed in both directions and the shorter one kept. A
        # stop sits on one side of the road; on a divided road the router
        # would otherwise drive on to the next U-turn to "reach" a stop that
        # is across the carriageway. Buses run both ways and one line is
        # drawn for both, so the side does not matter.
        path: list[list[float]] = []
        leg_meters: list[int] = []
        snaps: list[int] = []
        flagged: list[str] = []
        for a, b, a_name, b_name in zip(points, points[1:], route["stops"], route["stops"][1:]):
            options = []
            for start, end, reverse in ((a, b, False), (b, a, True)):
                answer = fetch(
                    f"{OSRM}{start['lon']:.6f},{start['lat']:.6f};"
                    f"{end['lon']:.6f},{end['lat']:.6f}?overview=full&geometries=geojson"
                )
                time.sleep(1.1)
                if answer.get("code") != "Ok":
                    continue
                found = answer["routes"][0]
                line = [[round(lat, 6), round(lon, 6)] for lon, lat in found["geometry"]["coordinates"]]
                moved = max(
                    distance_m((p["lat"], p["lon"]), (w["location"][1], w["location"][0]))
                    for p, w in zip((start, end), answer["waypoints"])
                )
                options.append((found["distance"], line[::-1] if reverse else line, moved))
            if not options:
                raise SystemExit(f"Route {number}: no road found from {a_name} to {b_name}")
            meters, line, moved = min(options, key=lambda option: option[0])
            direct = distance_m((a["lat"], a["lon"]), (b["lat"], b["lon"]))
            if meters > 1.6 * direct + 150:
                flagged.append(f"{a_name} -> {b_name}: {meters:.0f} m by road, {direct:.0f} m straight")
            if path and path[-1] == line[0]:
                line = line[1:]
            path.extend(line)
            leg_meters.append(round(meters))
            snaps.append(round(moved))

        straight = sum(
            distance_m((a["lat"], a["lon"]), (b["lat"], b["lon"]))
            for a, b in zip(points, points[1:])
        )
        result[number] = {
            "name": route["name"],
            "color": route["color"],
            "start": route["stops"][0],
            "end": route["stops"][-1],
            "stopIds": [p["id"] for p in points],
            "stopNames": route["stops"],
            "path": path,
            "roadMeters": sum(leg_meters),
            "straightMeters": round(straight),
            "legMeters": leg_meters,
            "stopToRoadMeters": snaps,
        }
        print(
            f"Route {number}: {len(path)} points, {sum(leg_meters) / 1000:.2f} km by road "
            f"({straight / 1000:.2f} km stop to stop in straight lines); legs {leg_meters}"
        )
        for line in flagged:
            print(f"     CHECK: {line}")

    unused = sorted(set(stops) - used)
    print("stops not on any route:", unused or "none")
    OUTPUT.write_text(
        json.dumps(
            {
                "note": "Road paths worked out by a routing service from the "
                "official stops. To be checked on the map before use.",
                "routes": result,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
