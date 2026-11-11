# Verified route and stop data

The app reads its bus routes and stops from two GeoJSON files in
`assets/data/`. They are empty until the university transport office confirms the
real routes. **Only verified data belongs there.** Sample data lives in
`assets/demo/` and is used only when the app is built with
`--dart-define=DEMO_DATA=true`.

Coordinates are WGS84, in GeoJSON order: `[longitude, latitude]`.

## stops.geojson

A `FeatureCollection` of `Point` features.

| Property | Required | Meaning |
|---|---|---|
| `id` | yes | Unique id, for example `rupatoli` |
| `name` | yes | Name shown to passengers |
| `description` | no | Extra detail, such as a landmark |

```json
{
  "type": "Feature",
  "properties": { "id": "rupatoli", "name": "Rupatoli" },
  "geometry": { "type": "Point", "coordinates": [90.3469, 22.6781] }
}
```

## routes.geojson

A `FeatureCollection` of `LineString` features, each drawn along the roads the
bus actually uses, in travel order.

| Property | Required | Meaning |
|---|---|---|
| `id` | yes | Unique id |
| `name` | yes | Route name shown to passengers |
| `color` | no | `#RRGGBB`. A palette colour is assigned if missing |
| `start` | no | Name of the starting point |
| `end` | no | Name of the ending point |
| `stops` | no | Stop ids in travel order, each present in `stops.geojson` |
| `active` | no | `false` hides the route as not running. Default `true` |

## What happens to bad entries

Entries with a missing id or name, a duplicate id, the wrong geometry type or
invalid coordinates are skipped, never guessed at. The app reports how many
were skipped, and a route that names an unknown stop is reported too.

## Stops awaiting confirmation (assets/review/)

`assets/review/stops.geojson` has the same format as `stops.geojson`, but
holds official stop names with positions that were only looked up by name
and have not been confirmed. It is written by
`tools/data/build_review_stops.py` and read only when the app is built with
`--dart-define=REVIEW_STOPS=true`, which also puts an "Unconfirmed stop
positions" label on every screen that shows them.

To confirm a stop: check its position on the map, correct the coordinates if
needed, add it to `assets/data/stops.geojson`, and remove it from the
`CANDIDATES` list in the script.

## The bus schedule (schedule.json)

`assets/data/schedule.json` holds the university's official timetable as it
was when the app was built. It is separate from the two GeoJSON files: a
route can have a timetable without being drawn on the map.

Passengers see this file only until an admin starts editing the schedule in
the app (Profile, Administration, Manage schedule). From then on the
schedule in the database is the one shown, and changing this file changes
nothing for them. Day-to-day changes belong in the app, not here.

Do not edit the JSON by hand. Edit the `SCHEDULE` list in
`tools/data/build_schedule.py`, which holds the schedule in Bangla exactly as
published, then run:

```bash
python tools/data/build_schedule.py
```

The script converts the times, adds an English transliteration of every
name, and stops with an error if a name has no transliteration (add it to
the `ENGLISH` table in the same file). Then run `flutter test`: the tests
check the file's counts and that each place's departures are in time order.

| Part | Meaning |
|---|---|
| `groups` | Who a timetable is for: Student, Teacher, Staff |
| `timetables[].route` | Route number as published, for example `01` |
| `timetables[].stops` | Stops in order. Empty when the schedule lists none |
| `timetables[].departures[].from` | The departure place |
| `timetables[].departures[].trips[]` | `time` (24-hour `HH:mm`) and `vehicles` as published |
| `recordedOn` | The day the schedule was copied from its source |

What the schedule does not contain, and the app therefore does not claim:
the days it applies on, the position of any stop, and the roads a route
follows.
