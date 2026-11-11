# Offline map

Status: **the offline map test passes on Android,** in airplane mode, at every
zoom from 10 to 18 and across the whole coverage, on a fresh install with no
connection and after a phone restart. Nothing has been tested on iOS.

## Coverage

| | |
|---|---|
| Centre | University of Barishal, 22.659967° N, 90.363381° E |
| Coverage | A rectangle around the bus routes: S 22.638, N 22.732, W 90.326, E 90.389 (about 10.5 by 6.5 km) |
| Camera limit | The same rectangle |
| Tiles held | That rectangle plus a margin of about half a screen at every zoom |
| Display zoom | 10 to 18, opening at 14 |

**The coverage was cut down on 11 November 2026 at the owner's request.**
The specification asked for a 15 km circle around the university, about 30
by 30 km. The buses use a small part of that, so the map now covers the
three routes and the university with about 2 km to spare on every side.
Outside the rectangle there is no map, and the camera cannot go there. If a
route is added beyond it, the coverage has to be widened and the package
rebuilt.

The camera centre cannot leave the rectangle. The margin of extra tiles is
there because the edges of the screen reach past the camera centre: without
it, rivers and roads stopped in a straight line when the camera sat at the
edge. These values live in `UniversityMapConfiguration`
(`lib/core/constants/university_map_configuration.dart`); a test fails if
the bundled archive was built for different values.

## Map data source

| | |
|---|---|
| Geographic data | OpenStreetMap, © OpenStreetMap contributors, Open Database Licence (ODbL) |
| Tiles | Protomaps basemap, daily planet build `20261110`, schema 4.15.2 |
| Format | PMTiles version 3, Mapbox Vector Tiles, gzip |
| How it is obtained | `tools/map/extract_basemap.py` copies only the needed tiles out of the planet build with HTTP range requests |
| Fonts | Noto Sans Regular, Medium and Italic glyph ranges from Protomaps basemaps-assets, SIL Open Font Licence 1.1 |

ODbL allows storing and redistributing the data offline with attribution. The
app shows "© OpenStreetMap" on the map at all times; tapping it shows the full
note, with the licence. That short form is what the OpenStreetMap Foundation's
attribution guideline (2021) asks for: credit to "OpenStreetMap" and a way to
reach the licence. Extracting a region from the Protomaps daily build is the
method Protomaps documents for making your own basemap. No tile server is
contacted by the app at run time.

### Change from the original plan

Phase 1 recommended generating the tiles ourselves with Planetiler from the
Geofabrik Bangladesh extract. That could not be done on the development
machine:

- Planetiler's OpenMapTiles profile needs the OpenStreetMap water-polygon
  dataset from `osmdata.openstreetmap.de`, which is unreachable from this
  network.
- It needs about 1.7 GB of downloads for a 4 MB result.
- Docker was not running, and drive `C:` has under 2 GB free.

The Protomaps extract gives the same OpenStreetMap data under the same
licence, as one archive we own and ship. The trade-off is that the tile schema
is Protomaps', so the styles are written for that schema. Switching generator
later would mean rewriting the two style files, nothing else.

## What is in the package

| Item | Location | Size |
|---|---|---|
| Vector tile archive | `assets/map/barishal_basemap_v3.pmtiles` | 2.58 MB |
| Manifest (size, SHA-256, source build, bounds) | `assets/map/barishal_basemap_v3.json` | 1 KB |
| Glyphs, 3 fonts × 256 ranges, trimmed | `assets/map/fonts/` | 1.0 MB |
| Light and dark styles | `assets/map_styles/` | 0.1 MB |

About 3.6 MB in total, down from 15.6 MB, so the package is **bundled with
the app**. There is no first-run download.

Package versions:

| Version | Change |
|---|---|
| 1 | First package: a 15 km circle's rectangle, 1,051 tiles, 4.04 MB |
| 2 | Added the edge margin: 1,370 tiles, 4.72 MB |
| 3 | Coverage cut down to the bus routes: 215 tiles, 2.58 MB. Fonts trimmed from 10.9 MB to 1.0 MB |

The styles use no sprite, so there are no sprite files to ship.

### Tiles and zoom levels

| Zoom | Needed for the coverage | Stored, with the margin |
|---|---|---|
| 8 | 1 | 1 |
| 9 | 1 | 2 |
| 10 | 2 | 4 |
| 11 | 2 | 12 |
| 12 | 4 | 16 |
| 13 | 6 | 30 |
| 14 | 20 | 42 |
| 15 | 70 | 108 |
| **Total** | **106** | **215** |

All 215 tiles requested were present in the source. The margin is
600 logical pixels of map at each zoom (about half a large phone screen),
capped at 20 km for the lowest zooms. The build script refuses to write an
archive that is missing any tile the coverage itself needs. Zoom 15 holds
about 60% of the bytes.

### Fonts

Each font comes as 256 files, one per block of 256 Unicode characters. The
labels in the covered area use only four blocks: Latin (0-255 and 256-511),
Bangla (2304-2559) and general punctuation (8192-8447).
`tools/map/trim_glyphs.py` reads every label in the archive, keeps the files
those labels need, and replaces every other file with an empty placeholder
of a few bytes. The placeholder is still a valid glyph file, so a request
for it succeeds and the character is simply not drawn.

Consequence: a stop or bus name typed in a script other than Latin or
Bangla will not show its letters on the map. It still shows correctly in
the app's lists.

## How it works in the app

1. `OfflineMapService` makes sure the package is installed, using
   `MapTileRepository` for the storage work.
   - **Android and iOS:** MapLibre Native cannot read files inside the Flutter
     asset bundle, so on first launch the archive and glyph files are copied
     to app storage (`<app support>/map/v2/`). A marker file is written last,
     so an interrupted copy is seen as interrupted rather than trusted. Older
     versions are deleted. Later launches skip the copy.
   - **Web preview:** read in place over HTTP range requests.
2. `MapStyleService.loadStyle()` reads `light.json` or `dark.json` and
   replaces two placeholders with local URLs:
   `pmtiles://file:///.../barishal_basemap_v2.pmtiles` and
   `file:///.../fonts/{fontstack}/{range}.pbf`.
3. The resolved style JSON is passed to `MapLibreMap`. Changing the app theme
   calls `setStyle` with the other style.

Checked by automated tests: the styles contain no `http` URL, no sprite, only
bundled fonts and only layers that exist in the tile schema; the installer
copies every file, skips a second copy, redoes an interrupted one and removes
old versions; the archive matches its manifest and the map configuration.

## Rebuilding the package

```bash
python -m venv tools/map/.venv
```

```bash
tools/map/.venv/Scripts/python -m pip install pmtiles
```

```bash
tools/map/.venv/Scripts/python tools/map/extract_basemap.py
```

```bash
tools/map/.venv/Scripts/python tools/map/fetch_glyphs.py
```

```bash
tools/map/.venv/Scripts/python tools/map/trim_glyphs.py
```

```bash
python tools/map/build_styles.py
```

`tools/map/inspect_basemap.py` lists the layers and attributes in the archive.
When the archive is rebuilt with newer data, raise the version in
`MapPackage` and in `extract_basemap.py` so installed copies are replaced.
Run `trim_glyphs.py` after every rebuild: it works out the needed fonts from
the new archive. Run `fetch_glyphs.py` first if a wider area needs fonts
that were trimmed away.

## Managing the map in the app

The Profile tab has an **Offline map** section. It shows the status, the area
covered, the date of the map data, the version and the space used, and offers
the actions that apply:

| Status | What it means | Actions |
|---|---|---|
| Checking | Looking at what is on the device | |
| Ready for offline use | Installed and usable with no connection | Check map, Check for update, Remove |
| Installing | Being copied into app storage, with a percentage | Cancel |
| Installation interrupted | A copy stopped part-way | Continue, Remove |
| Needs an update | An app update brought newer map data | Update map |
| Not on this device | Removed by the user | Install map |
| Something went wrong | The copy failed, usually for lack of storage | Try again |

How the specification's download features map onto a bundled package:

- **Download** is an install from the copy inside the app. It needs no
  network, so there is nothing to pause for connectivity. On the test phone it
  finished within a second or two.
- **Progress and percentage** are reported as files are copied.
- **Cancel** stops between files. What was copied is kept.
- **Resume and no duplicates:** an interrupted install copies only files that
  are missing or incomplete.
- **Retry** is available after a failure.
- **Integrity check** compares the installed archive with the manifest's
  SHA-256 and checks every glyph file is present. A damaged map offers
  "Install again".
- **Delete** removes all map data. The app does not silently put it back; the
  map screen then shows an "Install map" button.
- **Update:** newer map data ships inside app updates. When an update brings
  a newer package, the old one is replaced on the next launch. "Check for
  update" reports this honestly; there is no server to ask.
- **First run:** the map installs itself, so a new user sees the map without
  doing anything.

The home screen also shows "No connection. The map still works offline."
while the device has no network.

## Not built

- **Delivering a newer map without an app update.** This needs somewhere to
  host the package, which does not exist yet. It can be added once the
  Firebase backend is in place.
- **A paused state.** The install is a short local copy, so it can be
  cancelled and resumed but not paused.

## Known limitations and open questions

- **Not tested on iOS, and not yet after a phone restart.** The local
  `pmtiles://file://` source and `file://` glyph URLs work on Android,
  offline (see Verification).
- **A full phone can block installation.** Android refuses installs when less
  than about 500 MB is free. The release build is 38.8 MB and the app then
  copies about 15 MB of map data into its own storage on first launch. If that
  copy fails, the app shows "The map could not be opened" with a retry.
- **Bangla labels.** Labels use the English name when OpenStreetMap has one
  and the local name otherwise; 75 named features in the area have a Bangla
  name only. Simple Bangla names draw correctly on the test phone. MapLibre
  may not fully shape conjuncts and vowel signs that sit before their
  consonant, and such names have not been checked yet. If they are poor,
  Bangla-only labels can be hidden or replaced once verified English names
  exist.
- **Detail above zoom 15** comes from overzooming, as described above.
- **Fonts could be smaller.** All 256 ranges are shipped for each font so no
  label can ever need a missing file. Trimming unused scripts could save
  several megabytes after device testing.
- **Web** is a development preview. It loads MapLibre GL JS and the PMTiles
  reader from a CDN and is not an offline target.

## Verification

Done so far:

- Unit tests for the package, the styles and the installer (see above).
- Web preview, served locally from the bundled archive: the map opens centred
  on the university at zoom 14; zoom in to buildings and place labels; zoom
  out stops at 10 with the whole Barishal area visible; light and dark styles
  both render and switch with the app theme. All tile requests went to the
  local archive.

### Android device, online (10 November 2026)

Pixel 7 Pro, Android 17 (API 37), connected over wireless debugging, phone
online.

- **Fresh install of the release build** (38.8 MB, arm64): the first launch
  copied the map package into app storage and opened on the university at
  zoom 14 with roads, water, labels, the demo route and its stops. Also seen
  working in the debug build in both light and dark themes.
- **Automated sweep** (`integration_test/offline_map_test.dart`, profile
  build). The test moves the camera and asks MapLibre which features it
  actually rendered, so it cannot pass on a blank map. Features rendered at
  each step:

  | Step | Base features | Roads | Buildings | Labels |
  |---|---|---|---|---|
  | Zoom 10 | 83 | 10 | 0 | 11 |
  | Zoom 11 | 42 | 9 | 0 | 2 |
  | Zoom 12 | 99 | 33 | 0 | 16 |
  | Zoom 13 | 13 | 4 | 0 | 10 |
  | Zoom 14 | 24 | 10 | 5 | 3 |
  | Zoom 15 | 21 | 8 | 1,142 | 5 |
  | Zoom 16 | 31 | 20 | 230 | 6 |
  | Zoom 17 | 21 | 12 | 79 | 3 |
  | Zoom 18 | 12 | 6 | 29 | 0 |
  | Edge N, 14 km out | 47 | 6 | 2 | 0 |
  | Edge NE | 15 | 5 | 4 | 1 |
  | Edge E | 13 | 6 | 1 | 0 |
  | Edge SE | 4 | 1 | 0 | 0 |
  | Edge S | 4 | 2 | 0 | 1 |
  | Edge SW | 6 | 4 | 0 | 0 |
  | Edge W | 19 | 8 | 3 | 2 |
  | Edge NW | 67 | 10 | 4 | 1 |

  Zoom 17 and 18 are overzoomed from zoom 15 tiles and draw sharply. Zoom 18
  showed no base-map label only because the small area on screen had no named
  feature.
- **What this run does not prove:** the phone was online. The app's styles
  contain no network URL, but only the airplane-mode run shows that nothing
  is fetched.
- **Note on the result line:** every step above passed its checks, but that
  online run ended with a failure while closing the app (the map widget used
  a Riverpod `ref` during disposal). That bug is fixed, and the offline run
  below passed from start to finish with the fix in place. A clean online
  run after the fix was not repeated.

### Android device, airplane mode (10 November 2026)

Same phone, connected by USB.

**Full sweep: passed.** `run_device_map_test.ps1 -Label offline -ExpectOffline`
ended with "All tests passed".

- The test build replaced the app and wiped its data, so this was a first
  launch with no connection: the map package was copied into storage and
  drawn without any network.
- The test confirmed from inside the app that there was no internet, at the
  start and again at the end (a DNS lookup failed both times). The phone
  reported no active network before and after the run, and every screenshot
  taken during it shows the airplane-mode icon.
- Rendered feature counts at all 19 steps (zoom 10 to 18, eight coverage
  edges, and back to the university) were **identical to the online run**
  in the table above, labels included. Tiles and glyphs both came from the
  phone.
- Screenshots: `build/device_shots/offline/`.

**Fresh install of the release build, offline: passed.** After the sweep the
normal release build was installed (again with empty data) and started in
airplane mode. It drew the full map at the university with labels, the demo
route and its stops, and its log contained no errors.

One caveat on the conditions: when the sweep was started the phone reported
the airplane-mode switch off with Wi-Fi on but not joined to any network (no
active network, `ping` unreachable); airplane mode was switched on while the
test ran. The app-side checks at the start and end both found no internet.

Earlier partial runs, kept for the record. Before each of these the phone
reported airplane mode on, Wi-Fi off, no active network, and `ping` failed
with "Network is unreachable".

- **Reopening the installed app: passed.** The release build, which had been
  opened earlier while online, was force-stopped and started again in
  airplane mode. It drew the full map at the university: river, roads, road
  and place labels, the demo route and its stops. Screenshot:
  `build/device_shots/offline/cold_start.png`. The app's log shows no network
  error.
- **Fresh install with no network: passed as far as it ran.** The test build
  replaced the app and wiped its data, so the first launch had to copy the
  map package into storage with no connection. The test confirmed from inside
  the app that there was no internet (a DNS lookup failed), then drew:

  | Step | Base features | Roads | Buildings | Labels |
  |---|---|---|---|---|
  | Zoom 10 | 83 | 10 | 0 | 11 |
  | Zoom 11 | 42 | 9 | 0 | 2 |
  | Zoom 12 | 99 | 33 | 0 | 16 |

  These are identical to the online counts, labels included, so tiles and
  glyphs both came from the phone.
- That run was interrupted at zoom 13 when the map was touched and the app
  was closed, which is why the test now shows an on-screen notice and ignores
  touches. The sweep itself takes about a minute and a half.

**Map management on the phone: passed** (phone online for this check). In the
release build: "Check map" verified the installed archive against its SHA-256
and reported it complete; "Remove" asked for confirmation, then the Profile
tab showed "Not on this device" and the home tab showed the "Install map"
screen; "Install map" brought the map back within a second or two.

**Map package version 2 on the phone (phone online).**

- Installing the new build over the old one replaced the installed map on
  first launch: the Profile tab showed version 2, 15.1 MB.
- The full sweep passed with version 2, with the same feature counts as
  before at every step.
- Edge screenshots (north, south-east, west) show rivers and roads running
  to the edge of the screen, where version 1 stopped in a straight line.
- Two Bangla-only place names ("হাট সুপার সপ", "কাচা বাজার") drew correctly at
  zoom 17. Both use only simple vowel signs; names with conjuncts have not
  been checked.
- The airplane-mode sweep was not repeated with version 2. It uses the same
  code path as version 1, which passed offline.

**After a phone restart: passed (reported by the owner).** The phone was
restarted with airplane mode still on and the app opened with the map. This
step was checked by hand on the phone, not by the automated test.

### Still to do

- **iOS:** the whole test, when a Mac is available.

To repeat the Android sweep: connect the phone by USB with USB debugging on
(airplane mode switches off wireless debugging), enable airplane mode, and
run
`powershell -File tools\dev\run_device_map_test.ps1 -Label offline -ExpectOffline`.
Leave the phone alone until the red notice disappears.
