# Development log

## Current phase

**Phases 1 to 4 are complete, the ETA part of Phase 8 has been done early,
and Phase 5 (Firebase backend) is partly done.** The Firebase project
`bus-tracker-162c0` is set up and linked: Firestore, the Realtime Database,
their security rules and email sign-in are live. **Passengers need no
account** (owner's decision, 10 November 2026): bus data is readable by
everyone, and only drivers and transport office staff sign in. **Cloud
Functions are written but not deployed**, because the project is on the free
Spark plan and Functions need Blaze. That one decision blocks driver mode
(Phase 6). Details: FIREBASE_SETUP.md.

**The official bus schedule is in the app** (Routes tab), copied from
screenshots the owner supplied on 10 November 2026: 11 timetables and 101
departures for students, teachers and staff. The official routes are **not
on the map yet**: the schedule gives stop names for routes 01 to 03 only, and
no positions or road paths for any route.

Bus views, next-stop and arrival estimates are built and tested with sample
buses in tests only; the app has no source of buses until Phase 7, so on a
device they show "No live buses".

| Phase | Status |
|---|---|
| 1. Inspection and foundation | Done |
| 2. Map and visual foundation | Done (web preview, tests, and an Android phone) |
| 3. Offline map | Done on Android (airplane-mode test passed, management built). **iOS untested** |
| 4. Passenger application | Done. Bus views built and tested, but not reachable in the app until live data exists (Phase 7) |
| 5. Firebase backend | **Partly done.** Project, databases, rules, rule tests and sign-in done. Functions not deployed (needs Blaze). App Check and the Firestore data repositories not started |
| 6. Driver mode and GPS | Built without Cloud Functions (rules decide). **Not yet run on a phone** |
| 7. Real-time tracking | Built: live bus list, map markers, follow. Verified with emulator data only |
| 8. ETA, notifications, announcements | ETA service done early. Notifications and announcements not started |
| 9. Testing and optimisation | Not started |
| 10. Production readiness | Not started |

## Completed in Phase 2

- **Real vector map data.** A 4 MB PMTiles archive of OpenStreetMap data for
  the rectangle enclosing the 15 km circle, zoom 8 to 15, with the label fonts
  it needs. Bundled with the app. Details and licensing: OFFLINE_MAP.md.
- **Custom light and dark styles** (39 layers each) in a Google-Maps-like
  palette: warm off-white land, white streets, pale yellow arterial roads,
  soft green parks, light blue water, subtle buildings, coloured points of
  interest. Both are generated from one layer list by
  `tools/map/build_styles.py`, so they differ only in colour.
- **3D buildings.** Buildings are extruded from zoom 15, so tilting the map
  with two fingers gives the raised-building look. The default view is flat.
- **Map screen** (`UniversityMap`): opens on the university at zoom 14, never
  on the user's position; zoom limited to 10 to 18; camera limited to the
  covered area; style follows the app theme.
- **Map controls:** University (back to campus) and My location (asks for
  permission, explains refusals, offers Settings when that can fix it, and
  says so when the user is outside the covered area).
- **Draggable bottom sheet** with collapsed, half and full positions. It
  states that there are no live buses and lists routes.
- **Route and stop layers** as separate GeoJSON sources above the base map,
  re-attached after every style change. Route lines sit below the map labels.
- **Route and stop data model** with a documented GeoJSON import format
  (`docs/TRANSPORT_DATA_FORMAT.md`), a validating parser that skips and
  reports bad entries, and `BusRouteRepository` / `BusStopRepository`.
- **Verified and demo data kept apart.** `assets/data/` is empty. A labelled
  sample route in `assets/demo/` is loaded only with
  `--dart-define=DEMO_DATA=true`, and the map then shows a "Demo data, not
  official routes" label.
- **Map data credit** always visible on the map, with the licence note on tap.
- Services introduced: `MapStyleService`, `MapTileRepository`,
  `MapCameraController`, `TransportMapLayers`, `LocationService`,
  `BusRouteRepository`, `BusStopRepository`.
- Android location permissions and the iOS location usage text.

## Completed in Phase 3

- **Offline map management** (`OfflineMapService`, Profile tab section):
  status, area, data date, version and space used; install with progress and
  cancel; resume of an interrupted install without recopying finished files;
  retry after failure; integrity check against the manifest's SHA-256;
  remove; update when an app update brings newer data. See OFFLINE_MAP.md for
  how each requested download feature maps onto a bundled package.
- **The map installs itself on first run**, and a map the user removed is not
  silently put back.
- **A screen for when there is no map** (not installed, interrupted, failed,
  being prepared), with the action that fixes it.
- **`ConnectivityService`** and a "No connection. The map still works
  offline." label on the home screen.
- Ran the app on a Pixel 7 Pro (Android 17). Debug, profile and release
  builds all draw the map from the copy in app storage.
- Added an on-device test, `integration_test/offline_map_test.dart`, with a
  runner script, `tools/dev/run_device_map_test.ps1`. It sweeps zoom 10 to 18
  and the eight edges of the coverage, checks what MapLibre actually
  rendered, and in offline mode first proves the phone has no internet.
- Online results are in OFFLINE_MAP.md.
- Bug found on the device and fixed: the map widget used Riverpod's `ref`
  while being disposed, which throws in Riverpod 3.

## Completed in Phase 4

- **Routes tab:** a card per route with its name, ends, stop count, live bus
  count, colour and whether it is running. Tapping one opens it on the map.
- **Stops tab:** a card per stop with its name, description, coordinates and
  the routes that call there. Tapping one opens it on the map.
- **Selection on the map:** a selected route is drawn in full with only its
  own stops, its first and last stop filled in, and other routes faded. A
  selected stop gets a ring. Done with layer filters, so the map is never
  rebuilt.
- **Camera:** a selected route is fitted on screen and a selected stop is
  zoomed to, both centred in the part of the map the open sheet does not
  cover.
- **Tapping the map** selects the stop or route under the finger.
- **Home sheet:** shows the selected route (stops in travel order, each
  tappable), the selected stop (routes there, each tappable) or the selected
  bus, and opens itself far enough to read. Otherwise it shows the bus
  summary, bus list and route list.
- **Bus views:** bus card and bus details (number, name, route, status, last
  update, location, speed, direction, next stop, estimated arrival, follow
  control). Status is live, delayed or offline from configurable thresholds
  (20 and 60 seconds). An old position is described by its age and labelled
  as the last reported position. Speed and direction are hidden unless the
  position is live and the GPS fix is good.
- **States:** pulsing skeletons while loading, an error state with "Try
  again", and the existing empty states. The demo label is shown on every
  screen that lists demo data.
- **Motion:** cross-fade between sheet contents, animated sheet opening,
  animated camera moves, animated status pills.
- New pieces: `MapSelection`, `TransportLayerFilters`,
  `TrackingConfiguration`, `BusLocationRepository`, `Bus` / `BusLocation` /
  `TrackedBus` models.

Deliberately not done in Phase 4:

- **No demo buses.** A sample bus would be a fabricated position, so the bus
  views are exercised by tests only.
- **Next stop and estimated arrival** show "Not available" until the ETA
  service exists (Phase 8).
- **The follow control** records the choice; the camera movement that follows
  a bus comes with live positions (Phase 7).
- **Buses approaching a stop** and **announcements** need Phases 7 and 8.
- **Bus markers on the map** are Phase 7.

## Done ahead of its phase: ETA (Phase 8)

- **`RouteGeometry`** measures distance along a route's path and projects a
  position onto it.
- **`EtaService`** works out where a bus is on its route (distance along it,
  direction, next stop) and estimates arrival at a stop as distance along the
  route divided by current speed. Straight-line distance is never used.
- **Direction** comes from movement between two positions when available,
  otherwise from the GPS heading of a good, moving fix.
- **No estimate, with a stated reason,** when the position is missing or not
  live, the bus is away from its route, the direction is unknown, the bus is
  stopped, the speed reading is unreliable, the stop is not ahead, or the
  estimate would exceed 90 minutes. All limits are configurable.
- **Shown in the app's views:** bus details name the next stop and give the
  estimate or the reason; a selected stop lists the buses on their way,
  soonest first. Every estimate is labelled "(estimate)".
- Not included yet: speed averaged over recent positions, and historical
  travel times. Both need real trip data.

## Phase 5 so far: Firebase backend

Done:

- **Firebase project set up** (`bus-tracker-162c0`): Android, iOS and web
  apps registered, Firestore and the Realtime Database created in
  `asia-southeast1`, email and password sign-in switched on.
- **Security rules written and deployed** for Firestore and the Realtime
  Database. A user cannot change their own role or reactivate themselves;
  only an admin can. Trips cannot be written by any app. A bus position is
  accepted only from the driver of that bus's active trip, at most once a
  second, with a server timestamp and plausible values.
- **58 rule tests** run against the local emulators and pass
  (`firebase/test/`).
- **Cloud Functions written** (`firebase/functions/`, TypeScript): `startTrip`
  and `endTrip`. They compile. They have not been deployed or run.
- **Sign-in in the app, for drivers and staff only, with Google only**
  (owner's decision, 10 November 2026). One "Sign in with Google" button in
  the "Drivers and staff" section of the Profile tab, which then shows name,
  email and role. A new account has no special access until an admin grants
  it. The email and password screens, registration and password reset were
  removed at the owner's request, and email sign-in is switched off in the
  Firebase project.
- **No account for passengers.** The rules let anyone read routes, stops,
  buses, announcements, active trips and live positions; profiles and trips
  stay private, and nothing can be written without signing in. The "Student
  ID" field was removed from registration, since students no longer
  register. The stored field and its rule remain, unused.
- **Emulator switch:** `--dart-define=FIREBASE_EMULATORS=true` points the app
  at local emulators so testing does not touch the real project.
- The earlier email and password sign-in was checked end to end on the
  emulators before it was replaced. **Google sign-in has not been tried for
  real yet**: it needs a person to choose a Google account, on the phone.
- Bug found in the earlier check and fixed: straight after a first sign-in,
  the Profile tab did not show the role, because it had started listening
  before the profile was written. The profile is now re-read after sign-in,
  and a test covers it.

Not done:

- **Functions are not deployed** (Blaze plan needed), so no trip can start
  and no driver can publish a position yet.
- **No tests for the functions themselves.**
- **App Check** is not set up.
- **Firestore-backed repositories** for buses, routes, stops and
  announcements are not written; the app still reads routes and stops from
  the bundled GeoJSON files. `firebase_database` and `cloud_functions` are
  not added to the app yet.
- **No admin screens.** The first admin is made in the Firebase console
  (FIREBASE_SETUP.md).
- **Sign-in has not been tried against the real project**, only against the
  emulators, to avoid creating test accounts in it.
- **iOS is not linked**: `GoogleService-Info.plist` must be generated on a
  Mac.

## The official schedule

- **Data:** `assets/data/schedule.json`, written by
  `tools/data/build_schedule.py` from the Bangla text of the university's
  Bus Schedule screen. Student routes 01 to 03, teacher routes 04 to 07,
  staff routes 04, 05, 06 and 08.
- **Routes tab** now has two tabs. "Schedule" (shown first): choose Student,
  Teacher or Staff, then a route, and see every departure from each end with
  the vehicles named for it, then the route's stops. "On the map": the routes
  that are drawn on the map, as before.
- Bangla is shown as published, with an English transliteration beside it.
  The transliterations are this project's, not the university's.
- Bundled with the app, so it works offline.

What the app deliberately does not do with it:

- **No "next bus" or "runs today".** The schedule does not say on which days
  it applies, and the app says so on the screen.
- **No route lines or stop markers for the official routes.** The schedule
  has no coordinates. Placing stops needs positions confirmed by someone who
  knows them.
- **Routes 04 to 08 show no stops**, because the source lists none.
- The vehicles are shown as text and are not linked to tracked buses yet.

How the stop list is read (explained by the owner, 10 November 2026): the
first and last names are where the route starts and ends, the bus runs both
ways between them, and the names between are where passengers get on and
off. The screen marks the two ends "Start / end" and says this.

### Stop positions: searched, not confirmed

`tools/data/find_stop_candidates.py` searched the OpenStreetMap data in the
offline map for each official stop name and wrote the matches to
`tools/data/stop_candidates.json`. **None of these are in the app.** A match
is a landmark with a similar name, not a confirmed boarding point.

| Result | Stops |
|---|---|
| A likely match | University, Nuria School, Kathaltola (a mapped bus stop), TTC Main Gate, Thana Council Main Gate, Rupatoli Housing, Notun Bazar, Bottola Mor, Chowmatha Mor, Bangla Bazar Mor, Nathullabad |
| Only something nearby | Amtala Mor (Amtola Lake) |
| Doubtful | Opsonin Mor (the only match is the Opsonin factory, which is off the route) |
| Not found | Barishal Club, Toll Ghar, Munshi Garage, Karim Kutir, College Avenue, Trust Bhaban |

Each needs the owner's confirmation or a corrected position before it goes
on the map. The online OpenStreetMap search servers were overloaded on the
day, so only the bundled data was searched.

**Review build.** At the owner's request the 13 found positions (the 11
likely ones, Amtala Mor and the doubtful Opsonin Mor) can be shown on the
map for checking. They live in `assets/review/stops.geojson`, written by
`tools/data/build_review_stops.py`, and are loaded only with
`--dart-define=REVIEW_STOPS=true`. The app then shows "Unconfirmed stop
positions, for checking only" on the map and on the Stops tab, and each
stop's description says what was matched. There are no route lines, because
the roads each route follows are not known. A normal build never shows these
stops. When a position is confirmed or corrected it moves to
`assets/data/stops.geojson` and is deleted from the review file.

Uncertain points in the source, to confirm with the transport office:

- Whether more routes exist beyond those visible in the screenshots (the
  route row scrolls sideways).
- The days and dates the schedule applies to.
- The source spells some names two ways ("বৈকালি" and "বৈকালী", "কাঠালতলা"
  and "কাঁঠালতলা"). Both are kept as written and treated as the same name
  in English.

## Admin: managing stops

Asked for by the owner on 10 November 2026: an admin should be able to add,
move, rename and delete stops (and later buses and the schedule) from the
app, without a new release. Stops are the first part.

- **Stops now also come from the database.** The app shows the stops in the
  `stops` collection together with the bundled data. Anyone can read them;
  a change reaches every phone within seconds, and the phone keeps its last
  copy for offline use.
- **Manage stops** (Profile tab, Administration, admins only): the list of
  stops, Add stop, tap a stop to edit it, and delete with a confirmation.
- **Stop editor:** the admin moves the map until a fixed pin is on the stop,
  types a name and an optional note, and saves. The pin's coordinates are
  shown as the map moves. Positions outside the map area are refused.
- **Copy and paste coordinates** (asked for by the owner): in the editor,
  "Paste coordinates" takes what Google Maps copies (`22.690260, 90.359400`),
  degrees-minutes-seconds, or a full Google Maps link, and moves the pin
  there; the copy button puts the pin's coordinates on the clipboard in the
  same form. Text that is not a position, a short `goo.gl` link (which holds
  no position) and places outside the map area are refused with a reason.
- **Suggested positions:** the positions found by name in OpenStreetMap are
  offered to the admin as starting points. Passengers never see them; one
  becomes a stop only when the admin opens it, checks the pin and saves.
- **Security:** the screens are hidden from anyone who is not an active
  admin, and, independently of that, the database rules refuse the change
  (already covered by the rule tests).

Not done yet:

- Editing buses, the schedule, routes and announcements.
- Drawing a route's line. Stops saved here appear as dots on the map; they
  are not joined into routes.
- The schedule's stop names are not linked to these stops.
- A stop has one name. Bangla goes in the note for now.

## Admin: managing the schedule

The second admin editor, after stops.

- **The schedule can now live in the database**, one document per route and
  passenger group in the `timetables` collection. Anyone can read it; only an
  admin can change it.
- **Which schedule passengers see:** the one built into the app until the
  database holds at least one timetable; from then on only the database's.
  A change reaches every phone within seconds, and the phone keeps its last
  copy for offline use.
- **Manage schedule** (Profile tab, Administration, admins only):
  - With an empty database, "Start editing the schedule" copies the built-in
    schedule (11 timetables) into the database in one step.
  - Then: routes listed per group (Student, Teacher, Staff), "Add route",
    and tap a route to edit it.
- **Route editor:** the route number; departure places, each with its
  departures (a time and the buses, in English, Bangla or both); and the
  stops in order, with move up, move down, rename and remove. Times can be
  typed (`8:30 AM`, `16:05`) or picked on a clock, and are kept in order.
  Nothing changes for passengers until "Save route". Deleting a route asks
  first, and leaving with unsaved changes asks first.
- **Checks before saving:** a route number, no second route with the same
  number in the group, at least one departure place, and at least one
  departure at each place.
- **Security:** hidden from anyone who is not an active admin, and refused
  by the database rules regardless (4 new rule tests).

Not done yet:

- The schedule still has no days of the week.
- The buses on a departure are text, not links to the buses that will be
  tracked.
- A schedule stop is a name; it is not linked to a stop on the map.
- Two admins editing the same route at once: the last save wins.

## Admin: managing buses

The third admin editor, after stops and the schedule.

- **Manage buses** (Profile tab, Administration, admins only): the list of
  buses with each one's route, driver and whether it is in service; "Add
  bus"; tap a bus to edit it; delete from the editor, with a confirmation.
- **Bus editor:** number, name, optional registration number, a route chosen
  from the route numbers in the schedule, a driver chosen from the accounts
  whose role is driver, and an "In service" switch.
- **Checks before saving:** a number and a name; no second bus with the same
  number; a driver can have only one bus (the trip functions rely on that).
- **Passengers now see the buses in service** in the app's bus list, each
  shown as having reported no position, which is true until tracking exists.
  A bus that is not in service is hidden from them.
- **Drivers list:** read from the database by an admin only; the rules
  refuse that list to everyone else (2 new rule tests).
- **Security:** hidden from anyone who is not an active admin, and refused
  by the database rules regardless.

- **Buses named in the schedule** (asked for by the owner, 11 November
  2026): Manage buses reads the bus names out of the schedule's departures
  and offers the ones not yet in the list, 27 from the official schedule.
  "Add all" adds them in one step; tapping one opens it in the editor first.
  A bus's number is its English label in the schedule and its name is the
  Bangla label. A bus gets a route only when the schedule uses it on a
  single route number; the rest get none, because the schedule does not say
  which route is theirs.

Not done yet:

- A bus's route is a schedule route number. It is not yet a route drawn on
  the map.
- The buses in the list are separate from the bus names in the schedule's
  text: renaming one does not change the other.
- Not tried end to end on the emulators or the phone; app tests and rule
  tests only.

## Admin: managing people

Manage people (Profile tab, Administration, admins only) replaces the script
and the console for everyday role changes.

- Lists everyone who has signed in, with their email, what they may do and
  whether the account is active, and finds a person by name or email.
- Tapping a person changes their access: Passenger (no special access),
  Driver or Admin, and an "Account active" switch.
- Making someone an admin asks for confirmation.
- A driver who stops being a driver, or is deactivated, is taken off their
  bus in the same step, after a confirmation that says so.
- An admin cannot change their own access, so there is always at least one
  admin and nobody locks themselves out.
- Security: only an admin can read the list or change a role; the database
  rules enforce that (2 more rule tests).

Not done yet:

- An account cannot be deleted from the app, only deactivated.
- Not tried end to end on the emulators or the phone; app tests and rule
  tests only.

## Driver mode and live tracking (Phases 6 and 7)

Built on 11 November 2026, **on the free Firebase plan, without Cloud
Functions**. That is a deviation from the specification, which asks for
trusted backend code to start a trip. The owner has not agreed to the paid
plan, so the same decisions are made by the Realtime Database's security
rules instead. They are still enforced by the server, not by the app.

How a trip is authorised without a server function:

- The Realtime Database cannot see Firestore, so it keeps two small notes of
  its own: `admins/{uid}` (who is an admin) and `busDrivers/{busId}` (which
  driver a bus is assigned to). Only an admin can write either.
- The app copies them across whenever an admin changes a person or a bus,
  and again whenever Manage buses is open, so a missed copy heals itself.
  `tools/dev/sync_tracking_access.js` does the same from this computer.
- `activeTrips/{busId}` can be written only by that bus's assigned driver;
  `liveLocations/{busId}` only by the driver of the active trip, at most
  once a second, with a server timestamp and plausible values. An admin can
  end any trip. 30 rule tests cover this.

Driver mode (Profile tab, "Your bus", drivers only):

- Shows the driver's bus, and "Start trip". Starting asks for location
  permission if needed, opens the trip, and shares the phone's position
  about every 5 seconds until "End trip".
- **Background GPS:** on Android the positions come from a foreground
  service with a visible notification (the `geolocator` plugin's location
  service), with a wake lock. It is the operating system delivering
  positions, not a timer in the app.
- If the app is closed mid-trip and opened again, it offers to resume
  sharing or end the trip.
- Changing a bus's driver, taking it out of service or deleting it ends any
  trip in progress on it.

What passengers see:

- Every bus in service, with the position its driver last reported: live
  within 20 seconds, delayed within 60, offline after that. A bus that is
  not on a trip has no position, and the app says so.
- **Bus markers on the map**, coloured by how fresh the position is, with
  the bus number. Tapping one selects the bus. "Follow this bus" keeps it in
  view as it moves.
- Speed, direction, next stop and arrival estimates use the existing ETA
  service. **Arrival estimates stay unavailable for the official routes**,
  because those routes have no path on the map yet.

Not done, or not verified:

- **Driver mode has not been run on a phone.** Background sharing with the
  screen off, the notification, and battery use all need a real trip.
- **Not built:** trip history (the specification's `trips` collection was to
  be written by a Cloud Function), push notifications, a 3D bus on the map.
- **The free plan allows 100 phones connected to the Realtime Database at
  once.** Beyond that, new passengers get no live positions. This is the
  free plan's limit and the main reason to move to the paid plan later.
- The marker is a coloured dot, not yet the 3D bus the owner prefers, and it
  does not show the direction of travel.
- A phone with a wrong clock will misjudge how fresh a position is, because
  freshness compares the server's timestamp with the phone's clock.
- Android 13 and later can hide the trip notification if the driver has
  refused notifications; the sharing still runs. The app does not ask for
  that permission yet.
- iOS background location is configured but cannot be built or tested here.

## Official routes on the map (11 November 2026)

The owner placed all 19 official stops in the app and asked for the roads to
be drawn.

- **Stops matched to routes.** `tools/data/build_routes.py` lists, for each
  student route, the owner's stops in the schedule's order. Where the
  owner's name differs from the schedule's, they were paired by position:
  "Nooria School" for Nuria School, "Rupatoli" for Rupatoli Housing, "Toll
  Plaza" for Toll Ghar, "Munsi Garaz" for Munshi Garage, and the two Amtala
  stops: "Amtolar Mor(barishal club bus)" on route 01 and "Amtala Mor(RHD
  GATE)" on route 03.
- **Road paths from a routing service.** Each leg between two stops was
  routed on OpenStreetMap roads (OSRM), in both directions, keeping the
  shorter. Routing both ways removed two artifacts of a first attempt: a
  loop round the Rupatoli roundabout and a detour off the highway at
  Kathaltola, both caused by a stop sitting on one side of a divided road.
- **Result:** route 01 is 7.0 km, route 02 is 9.3 km, route 03 is 8.2 km.
  Every stop is within 10 m of the road it was matched to.
- **Stored in the database** (`routes` collection, ids `01`, `02`, `03`,
  the same numbers buses are assigned to), and the app now reads routes from
  there as it does stops.
- Seen in the web preview against the live project: three coloured lines
  through their stops.

What is not certain:

- **The path between two stops is the routing service's choice of roads.**
  It is the likely path, not a recorded one. The owner should look at each
  route on the map. The leg most open to question is route 02 from Karim
  Kutir to the university (7.3 km, with no stop in between).
- Routes 04 to 08 are not drawn: the schedule lists no stops for them.
- There is no route editor in the app. To change a path, change the stops or
  the list in `build_routes.py`, run it, and run `tools/dev/upload_routes.js`.

## Map package version 3: a smaller map

Asked for by the owner on 11 November 2026: the buses use a small area, so
the offline map does not need to cover 15 km in every direction.

- **Coverage** is now a rectangle around the three routes and the
  university with about 2 km to spare: about 10.5 by 6.5 km, where it was 30
  by 30. This replaces the specification's 15 km circle.
- **Tiles:** 215 instead of 1,370; 2.58 MB instead of 4.72 MB.
- **Fonts:** 1.0 MB instead of 10.9 MB. Only the character blocks the map's
  labels use are kept (Latin, Bangla, punctuation).
- **Whole package:** about 3.6 MB instead of 15.6 MB.
- Installed copies are replaced on first launch, as with version 2.

Details and the consequences are in OFFLINE_MAP.md.

## Map package version 4: a band around the routes

The owner found version 3 still too big and asked for an even surround
around the routes, built from small cells (11 November 2026).

- From zoom 13 up, a map tile is kept only if it comes within 1.5 km of a
  route (plus a 250-pixel margin so edges are not cut off on screen). The
  kept tiles form a band of even width along the roads. Map tiles are
  square, so the cells are squares, not hexagons.
- 108 tiles, 2.00 MB (version 3: 215 tiles, 2.58 MB). With the fonts the
  package is about 3.0 MB.
- The camera is limited to the band's outline, 9.4 by 5.5 km. **Inside that
  outline but away from a route there is no detailed map**: zooming in there
  shows only the coarse zoom-12 picture.
- Route 02 was also corrected at the owner's direction: after Karim Kutir it
  runs to Chowmatha and then shares the stops down to the university (12
  stops).
- `OFFLINE_MAP.md` still describes version 3's rectangle and tile counts.

## Announcements (11 November 2026)

- An admin posts a short notice (title and message) under Profile,
  Administration, Announcements. It can be changed, hidden from passengers
  without deleting it, or deleted after a second confirming tap.
- Every phone shows the current notices at the top of the home sheet, with
  the date. Nobody needs to sign in to read them.
- Stored in the `announcements` collection, whose rules were already in
  place: anyone reads, only an admin writes.
- 11 app tests. Not tried on the emulators, the phone or the live project.
- **No push notification.** A notice is seen when the app is opened. Making
  phones buzz needs a server to send the message.
- The map zoom-out limit was also raised to 11.5 the same day, so the widest
  view is the routes with about as much again around them.

## Arrival times on the real routes (11 November 2026)

- The arrival estimates built earlier now have real routes to work on. A
  test puts a position half way along the real route 01 and gets a sensible
  time to the university.
- **The driver chooses the route when starting a trip** ("Route for this
  trip" under Your bus). Most buses in the schedule run several routes, so a
  bus has no fixed route; the trip does. While a trip is running the bus is
  treated as being on that route, and arrival times follow it.
- Not verified with a moving bus. Estimates need a live position with speed
  and a direction, so nothing shows until a real trip runs.
- Routes 04 to 08 have no path, so a trip on one of them gets no estimates.

## Map page redesign (11 November 2026)

Asked for by the owner: the route lines, the bus marker, its jumpy movement
and the look of the map page. This replaces the earlier top-view bus icon.

### Bus marker and movement

- **Marker** (`bus_map_layer.dart`): a round badge in the status colour with
  a white rim, a shadow and a bus pictogram (dark instead of white when the
  status colour is light, as in the dark theme). The badge stays upright. A
  small pointer on its rim turns to the direction of travel, and is left out
  when the direction cannot be trusted (stopped, weak fix, not live), so the
  map never shows a direction it does not have. A live bus has a soft ring
  pulsing around it. The pictures are painted by the app; there are no image
  files.
- **Smooth movement** (`bus_motion.dart`): a bus reports every few seconds.
  The marker used to jump to each new position. Now it glides from where it
  is drawn to the new position, taking as long as the gap between the last
  two reports (never under 0.8 s or over 7 s), and the pointer turns the
  short way round. It only ever moves between positions the bus really
  reported: nothing is predicted beyond the last report. A jump of more than
  600 m places the marker instead of sweeping it across the map.
- The map redraws the markers about 15 times a second, only while a bus is
  live or gliding or a stop is picked.
- It is still a flat marker, not the 3D bus model the owner prefers.

### Route lines

- With every route showing, routes that share a road are drawn **side by
  side in lanes**, like a transit map, so no route hides another. Each has a
  thin casing in the map's background colour.
- The selected route is drawn bold on the middle of the road with a soft
  glow in its colour; the others fade back.
- **Stubs are not drawn.** The saved road paths contain tiny there-and-back
  stubs (2 to 16 m) where the routing snapped to a side road at a stop. They
  showed as blobs and spikes on the line. `TransportGeoJson.withoutStubs`
  leaves out stubs up to 25 m when drawing. The saved paths are unchanged,
  and arrival times still use them as saved.

### Stops

- Seen from far away (below zoom 13) a stop is a white dot with a dark ring.
  Closer in it is a **bus-stop badge**: a rounded square with a sign on a
  pole (`stop_map_layer.dart`).
- The first and last stop of the selected route have a larger, darker badge.
- **The picked stop is animated**: its badge, in the app's main colour, pops
  up to a larger size and a ring keeps rippling out from it.
- The same badge is used for stops in the sheet and in the Stops list, where
  it pops into place once.

### The page around the map

- **Route chips** float across the top: "All routes" and one per route in
  its colour. Tapping a chip puts that route in focus; tapping it again, or
  "All routes", lets go.
- The sheet has a larger heading, bus cards with the same badge as on the
  map, and route cards with the route's colour down the side.
- The two map buttons are one rounded block. The compass sits below the
  chips (on Android and iOS; the web map cannot move it).

### Second pass, after the owner tried it on the phone

- **Stop badges were small and blurred.** The marker pictures were painted
  at their design size, and the map stretched them on the phone's dense
  screen. All marker pictures (stops and buses) are now painted at three
  times their design size (`mapImageScale`) and drawn that much smaller, so
  they stay sharp. Stop badges are also larger: about 25 pixels across at
  zoom 13, growing to 60 at zoom 18, in a strong dark badge with a light
  rim. The picked stop's badge is larger again.
- **A tap near a stop or bus picks it.** A tap used to need to land exactly
  on the marker, which is hard on a small dot. Now anything within about a
  fingertip (18 logical pixels) counts, and the nearest one wins.
- **Bus details are cards** (`bus_details_view.dart`): a card for the next
  stop and its arrival estimate, then speed (with a bar that fills to the
  reported speed), direction (an arrow turned to the heading), route, last
  update and location. The cards slide in one after another, and a value
  cross-fades when it changes. What is not known still reads "Not
  available", drawn quieter.
- **Stop details** in the sheet: larger heading with the stop's badge, a
  location card with a button that copies the coordinates, buses on the way
  as cards with the estimate on a pill, and routes as cards.
- **Stops tab**: each stop is a card with its badge, description, the
  routes that call there as coloured pills, and its coordinates.
- Shared pieces: `shared/widgets/info_tile.dart` (`InfoTile`, `SoftCard`,
  `Appear`, `SectionTitle`), `route_card.dart`, `stop_badge.dart`.

### What was checked, and what was not

- Web preview, with the labelled TEST bus written to the live database
  (`tools/dev/simulate_test_trip.js`, removed again when the run ends):
  over 10 seconds the marker was redrawn 154 times, every 67 ms, moving an
  even 0.69 to 0.70 m each time, with no frame standing still and no jump.
- Seen in the preview: the bus details cards with a live TEST bus, the
  stop details, the Stops tab, and the stop badges zoomed in.
- Seen in the preview in light and dark: lanes, the selected route's glow,
  the chips, the cards, the stop badges, a picked stop's badge and ripple.
- **Not checked on the phone**: how smooth the movement and the animations
  are there, and where the compass sits. The stop animation's frame rate
  was not measured (the preview pane was in the background, where browsers
  allow one frame a second).

## Test the system, bus destinations, Routes page (11 November 2026)

### Test the system (Profile → Try it out)

- Anyone can run pretend buses to see the app at work, without a driver
  and without touching the server. `features/test_drive/`.
- **It stays on the device.** The buses are worked out on the phone and put
  next to the real ones in `trackedBusesProvider` through
  `localTestBusesProvider`. Nothing is written to Firestore or the Realtime
  Database, so no other phone sees them and no real data is changed. It
  works without a connection once the routes are on the phone.
- **They cannot be taken for real buses.** Each is numbered "TEST n" and
  named "Test bus, only on this phone", and while a test runs the map page
  carries a "Test mode: TEST buses are pretend" label with a Stop button.
  Stopping removes them all.
- The screen: add a bus (route, which way it sets off, 10 to 60 km/h, a
  start delay up to 60 s), or "Add a set" (one bus each way on up to three
  routes, different speeds, starts 8 s apart). At most 12 buses.
- A test bus follows its route's saved path at its speed, reports every
  2 s like a driver's phone, waits 20 s at the end and drives back, so a
  test can be left running.
- Real data source is now `reportedBusesProvider`; `trackedBusesProvider`
  is that plus any test buses.
- `tools/dev/simulate_test_trip.js` and `simulate_test_fleet.js` still
  exist for testing through the real database (they do write to it, and
  clean up after themselves). The in-app test replaces them for everyday
  checks.

### Where a bus is going

- Bus cards and the bus details show "From → To" (for example
  "University (1st Gate) → Barishal Club"), from the bus's direction along
  its route (`bus_journey.dart`).
- It is shown only for a live bus on its route that is moving in a clear
  direction. Otherwise the line is left out; nothing is guessed.

### Routes page

- **Schedule tab:** the Student / Teacher / Staff buttons and the route
  chips are pinned at the top; the timetable scrolls beneath them, and a
  shadow appears under them once it has. Choosing another group or route
  shows the new timetable from its top.
- The timetable is cards: a summary (departures and places), one card per
  departure place with each time on a pill, and the stops on a numbered
  line with the two ends marked. Cards slide in one after another.
- **On the map tab:** route cards with the route's colour, its symbol, and
  a bus icon that turns green when one of its buses is live.

### Checked, and not

- 450 tests pass, including the test mode (where a bus is at each moment,
  delays, both directions, stopping, the limit) and the pinned selectors.
- Web preview: added a set, started it, saw the buses and the test label
  on the map and each bus's "From → To" in the list; scrolled the schedule
  with the selectors staying put.
- **Not checked on the phone.**
- Three tests that waited a fixed 50 ms and failed on a busy machine now
  wait for the state they check.

## Buses on their lines, direction switch, Stops and Profile (11 November 2026)

Asked for by the owner after trying the test mode on the phone.

### Buses follow their route line

Three things made a bus look as if it was not on its route:

- **Lanes.** With several routes showing, each line is set to one side in
  its own lane, but the bus was drawn on the middle of the road, so it sat
  on a neighbour's line. The marker is now set to the side with its own
  line (`TransportMapLayers.inLane`, using the same lane widths as the
  lines and the map's zoom). When its route is the selected one, which is
  drawn on the middle of the road, so is the bus.
- **Corners.** Between two reports the marker moved in a straight line and
  cut across bends. It now travels along the route's line
  (`BusMotionTracker` with `trackOf`, `RouteGeometry.locate`), and the
  pointer follows the road as it turns.
- **Stubs.** Test buses drove the tiny there-and-back stubs that the drawn
  line leaves out. They now drive the line as drawn.

What this does and does not do:

- A bus is put on its route's line only when it reports from within 40 m
  of it (the road's width and ordinary GPS error). Further away it is
  drawn exactly where it reported, so a bus that has left its route is not
  shown as if it were on it.
- Only the drawing moves. The reported position is unchanged everywhere
  else: details, arrival estimates, the driver's data.
- Still nothing is predicted beyond the last report.

### Bus markers are larger

- Drawn at 0.74 of their design size instead of 0.5: the badge is about
  52 pixels across. The pulse ring, the selection ring and the label moved
  out to match.

### Schedule: one direction at a time

- Under the route chips, pinned with them, a bar shows the direction
  ("University → Barishal Club") with a switch button. Tapping it shows
  the other direction's departures ("Barishal Club → University").
- The destination is the other end of the route's stop list, or, for a
  route that lists no stops, the other departure place. A route with one
  departure place has no switch.
- The summary counts that direction's departures, and the stops are listed
  in the order that direction meets them.

### Stops page

- A search box (name or description) and a chip per route, pinned above
  the list, with a count of what is shown. "No stop matches" when a search
  finds nothing.

### Profile page

- A header with the app's and the university's name and a line saying
  passengers need no account.
- Sections are rounded cards; rows that lead somewhere have their icon on
  a tinted tile (`SettingsTile`). The same card style now applies wherever
  `SectionCard` is used, including the admin screens.
- The page builds all its sections at once (it is short), instead of
  lazily.

### Checked, and not

- 466 tests pass.
- Web preview: test buses large and on their lines; the direction switch;
  the Stops search bar and chips; the Profile header.
- **Not checked on the phone**, including whether a bus sits exactly on
  its lane at every zoom.

## Route 02's stops, buses on the way, a smoother switch (11 November 2026)

### Student route 02 lists all its places

- The published schedule lists six places for route 02. The owner said
  (11 November 2026) that from Karim Kutir the bus goes to Chowmatha and
  then runs and stops as routes 01 and 03 do. The schedule's list now has
  all twelve: Notun Bazar (Tempo Stand), Munshi Garage, Opsonin Mor,
  Bottola Mor, Karim Kutir, Chowmatha Mor, Thana Council Main Gate, Amtala
  Mor, Rupatoli Housing, Kathaltola, Toll Ghar, University. The six added
  ones use the names route 03's list gives them. This matches the route as
  drawn on the map.
- Changed in two places, because the app shows the database's timetables
  when it has them, and it does:
  - `tools/data/build_schedule.py` and the rebuilt
    `assets/data/schedule.json` (the built-in schedule);
  - the live database: `timetables/student-02`, its `stops` field only.
    The departure times were not touched.
- **These six places are from the owner, not from the published
  schedule.** If the transport office's list differs, change it in
  Profile → Manage schedule.

### Buses on the way to a stop

- Each bus is a card: its badge and number, **which way it is going**
  ("University (1st Gate) → Barishal Club"), its route, the arrival
  estimate, and how far it still has to drive ("450 m away"). The soonest
  is marked "Next".
- The direction is the same one shown on bus cards, and is left out when it
  cannot be told.

### Direction switch on the schedule

- Switching direction no longer jumps to the top: the page stays where it
  was scrolled to.
- The old direction's times fade out as the new ones fade and slide in,
  the card's height eases to its new size, the words in the direction bar
  rise into place, and the count of departures fades to its new value.
- Choosing another route or group still starts from the top.

### Checked, and not

- 469 tests pass, including: the direction and distance on the cards, both
  directions present mid-transition and the scroll position unchanged
  after a switch, and route 02's twelve places.
- **Not seen working in the preview or on the phone.** The preview pane was
  being throttled and cropped during this round, so these three were
  checked by tests only.

## Teal Mint palette (11 November 2026)

The owner found Dark Crimson too red and chose "Teal Mint" from mock-ups of
several softer themes. Only the colours changed; shapes, motion, layout and
"dark is the default" stay as below.

- **Accent:** mint `#5FD4BC` (fills on dark), soft mint `#7FE0CB` (text and
  icons on dark, `theme.accent`), deep mint `#0A7563` (the light theme's
  primary, readable on white).
- **Surfaces:** neutral slate in dark (`#0F1318` → `#141920` → `#1A2028` →
  `#232A34`), cool white in light (`#F2F5F7`, white cards).
- **Status:** live `#46D369` (a yellow-green, so it is not taken for the
  mint), delayed `#F5B544`, **offline is grey** `#8A97A8`. Real errors have
  their own red (`AppColors.error`), no longer shared with "offline".
- **Route colours:** orange `#F2994A`, blue `#6FA8FF`, purple `#B79CFF` in
  `build_routes.py`, `routes_draft.json` and `AppColors.routePalette`.
  Updated in the live database the same day with
  `tools/dev/set_route_colors.js` (only the `color` field; paths and stops
  kept).
- The map styles were not changed: they are already neutral.
- The app icon stays the red pin, as chosen.
- 518 tests pass (palette and contrast tests updated); seen in the web
  preview in dark. Not checked on the phone or in the light theme on screen.
- The website's screenshots were retaken in the new theme.

## Dark Crimson redesign (11 November 2026)

The owner asked for the whole app in a "Dark Crimson" Material 3 design.
It was done through the central theme, so screens changed little: they
already read their colours and shapes from it.

### Where the design lives

| File | Holds |
|---|---|
| `core/theme/app_colors.dart` | The palette (`AppColors`) and status colours (`AppSemanticColors`: success, warning, offline, info, muted) |
| `core/theme/dark_theme.dart`, `light_theme.dart` | The two `ColorScheme`s, every role set by hand |
| `core/theme/app_shapes.dart` | Corner radii (`AppRadius`), shapes (`AppShapes`), motion (`AppMotion`) |
| `core/theme/app_spacing.dart` | The spacing scale |
| `core/theme/app_typography.dart` | The type scale |
| `core/theme/app_theme.dart` | `ThemeData`: every component's look, and `theme.accent` |
| `tools/map/build_styles.py` | The map's colours, light and dark; writes `assets/map_styles/` |

### Decisions

- **Dark is the default.** Light (warm ivory) and "follow the phone" are in
  Profile → Appearance. A choice already saved on a phone is kept.
- **No wallpaper colours.** The scheme is fixed; there is no dynamic colour
  package and no surface tint. Depth comes from four surface tones.
- **Primary is the full crimson** (`#E53945`) for fills. As text or an icon
  on a dark surface it is a little dim, so `theme.accent` gives the soft
  crimson (`#FF626B`) there; the component themes (navigation, tabs, text
  buttons, focus rings, progress) use it. Many widgets still use
  `colorScheme.primary` for small crimson text; it reads at about 4:1.
- **Offline buses are the palette's red** (`#EF6268`), no longer grey. Grey
  (`muted`) is kept for "not running" and "not known".
- **Icons:** Flutter's built-in Material Icons in the Rounded style
  throughout, filled for the selected tab and outlined for the others. No
  icon package was added.
- **Typeface:** the system one (Roboto on Android, San Francisco on iOS).
  Google Sans is not licensed for other apps and Roboto is not bundled.
- **Shapes:** buttons, chips and search fields are fully round; cards 20;
  sheets and dialogs 28.
- **Motion:** pages fade forwards on Android and slide on iOS; the tab icon
  pops as it is chosen; the theme eases across when switched; cards'
  entrance is skipped when the phone asks for reduced motion.
- **Map:** dark charcoal land, slate roads, muted green, deep blue water,
  nothing red; the light map is warm ivory. The stop badge is the theme's
  text colour, the picked stop crimson.

### Left as they were, on purpose

- **Route colours** come from the route data, not the theme, so a selected
  route keeps its own colour and matches its chip and card. On the owner's
  word (11 November 2026) the three routes were recoloured to the palette
  in the live database: 01 crimson `#E53945`, 02 blue `#72A9E8`, 03 green
  `#37C98B` (`tools/dev/set_route_colors.js`, which changes only the
  `color` field). `tools/data/build_routes.py` and `routes_draft.json` say
  the same, so uploading the routes again does not undo it.
- **Notification settings** were in the brief but the app has no
  notifications, so no such section was added.
- The loading skeleton is still static.

### Checked, and not

- 474 tests pass, including new ones: the palette values, layers getting
  lighter towards the front, text contrast on every surface in both themes,
  shapes, and dark as the default.
- Web preview, dark theme: map, Routes, Stops, Profile.
- **Not looked at:** the light theme on screen, the admin and driver
  screens in the new theme, and anything on the phone.

## Profile page, second pass (11 November 2026)

- **Top card rebuilt.** The app's short name ("BU Bus Tracker") with the
  university's English and Bangla names each on their own line, where the
  long name used to crowd one line. Under them a pill says who is using
  the app ("Passenger · no account needed", or "Signed in · Driver"), and
  a strip counts the routes, the stops and the buses live right now, from
  the same data the other tabs use.
- **Appearance** has a row saying which theme is in use above the three
  choices.
- **Offline map** status and the **sign-in** explanation have their icon on
  a tinted tile like the other rows; the sign-in button is full width.
- A small footer names the app and credits OpenStreetMap.
- 478 tests pass, with new ones for the card: its text, its three counts,
  and that it fits a 320-pixel-wide phone without overflowing.
- Seen in the web preview in the dark theme. **Not seen** signed in, in the
  light theme, or on the phone.

## Predictions, also offline (11 November 2026)

Asked for by the owner: predict where buses are and when they arrive, and
keep it working with no connection by saving what is needed on the device.

### What a prediction is, and is not

- A prediction is **never a live position**. It has its own marker (a
  dashed blue ring, label "~ ..."), its own section ("Predicted buses"),
  the word "Predicted" on each card, and a line saying what it rests on.
  The live code never sees one: "N buses live", arrival estimates and the
  bus list still use real positions only.
- Nothing is predicted for a bus, or a route and direction, that has live
  data. Live always wins.

### The two sources (`features/prediction/domain/prediction.dart`)

1. **Where a bus was last seen.** A real bus that was live recently is
   carried forward along its route from its last real position, in the
   direction it was going. It is dropped 45 minutes after it was last seen,
   or two minutes after it would have reached the end of its route (what it
   does next is not known), and at once when it is live again.
2. **The timetable.** A departure that should be on the road is placed
   along its route by the time since it left. Only one predicted bus per
   route and direction, and none where source 1 or a live bus covers it.

Both use a **speed per route and direction**: distance along the route
over time taken, stops included.

- **Learned** from real live buses: when one has covered at least 300 m of
  its route over at least 45 s, that stretch's speed is a sample; samples
  are blended (a new one moves the figure by a fifth). A gap of over 60 s,
  a bus over 60 m from its route, a position that is not live, speeds
  outside 5 to 70 km/h, and test buses teach nothing.
- **Assumed** until then: 20 km/h. The app says so on screen.

### On the device (`prediction_providers.dart`)

- `PredictionLearner` watches the real buses, learns speeds and remembers
  where each was last seen and which way it was going.
- `PredictionStore` writes both to the device's own storage at most every
  10 seconds while buses are live. Unreadable saved data is ignored.
- With no connection the engine needs only what is on the device: the
  learned speeds, the last-seen buses, the timetable and the routes (the
  timetable is built in; routes and edited timetables come from Firestore's
  own offline copy on Android and iOS).

### Where it shows

- **Map:** predicted buses under the live ones, on their route's line.
  Tapping one opens its route.
- **Sheet:** "Predicted buses" under the live ones, each with its
  direction, what it rests on, the vehicles the timetable names, and
  "Should reach <stop> about <time>".
- **Stop details:** "Predicted arrivals", up to five within 90 minutes,
  with a note that these are not live times.
- **Profile → Predictions:** switch them off, see what has been learned and
  when it was saved, and forget it.

### Limits to know

- **The timetable does not say which days it runs.** The app predicts from
  it every day and says so; on a holiday it will show buses that are not
  running.
- The assumed 20 km/h is a guess until real trips have been seen.
- A predicted bus moves at one steady speed: it does not know about traffic
  or how long the bus waits at a stop.
- On the web preview the routes are not kept offline.

### Checked, and not

- 518 tests pass, 40 of them new: positions from the timetable and from
  last seen, both directions, expiry, live buses taking precedence, no
  double counting, arrivals at a stop, learning (including what must not
  teach), saving and reading back, and the screens.
- Web preview with the real timetable: a predicted Route 02 bus on the map
  and its card in the sheet.
- **Not checked:** on the phone; with no connection; learning from a real
  bus (none has driven yet).

## Map page: following turns the map, key, colours (11 November 2026)

### Following a bus turns the map

- While a bus is followed the camera comes closer (zoom 16.6), leans
  forward 45 degrees, and **turns to face the way the bus is going**, as a
  navigation app does. Stopping returns the map to north-up and level.
- The camera travels with the marker frame by frame (about 30 times a
  second, where the marker alone is redrawn 15 times), so it does not
  catch up in steps with each report.
- The turn is eased: each frame the map turns 12% of the way to the bus's
  heading, the short way round, so it does not twitch. With no direction
  to trust (bus stopped, weak fix) the map keeps facing the way it was.
- The passenger's own zoom is kept while following (13.5 to 18).
- The bus is kept in the middle of the part of the map the sheet does not
  cover, whichever way the map is turned
  (`MapCameraController.centreFor`).
- A "Following Bus N" label with a Stop button sits under the route chips,
  since the map is moving by itself.

### Map buttons

- **Map key**: a sheet explaining each marker (live, delayed, offline,
  predicted, stop) and the route lines, drawn with the same badges the map
  uses.
- **All routes**: zooms out to every route and lets go of what was picked.
- University and My location as before.

### Colours

- The map's dark style was tuned for the crimson theme. It is now a cool
  slate that matches the mint theme's surfaces; the light style is a cool
  white. Nothing in the base map is mint: the accent stays for buses and
  what is selected.
- **Profile top card:** it faded from mint to a shade its own text could
  not be read on, in both themes. It is now one tonal colour
  (`primaryContainer`) with the text made for it, and a test checks the
  contrast in dark and light.
- The other pages (Routes, Stops, the test screen, Profile's sections)
  were looked at in both themes; no other colour fault was found. The
  theme line no longer says "warm ivory".

### Checked, and not

- 530 tests pass, with new ones for where the camera looks at any bearing,
  the eased turn, the map key, "All routes", and the following label.
- Web preview: the map colours, the four buttons, the Profile card.
- **Not seen:** the map actually turning while following. The preview
  would not show the lower half of the screen, so Follow could not be
  pressed there. It needs trying on the phone.

## Map package version 2

- A margin of extra tiles (half a large screen at each zoom, capped at 20 km)
  is stored around the covered rectangle, so rivers and roads no longer stop
  in a straight line when the camera is at the edge. 1,370 tiles, 4.72 MB
  (version 1: 1,051 tiles, 4.04 MB).
- On the phone, installing the new build over the old one replaced the
  installed map by itself: the Profile tab went from version 1 to version 2.

## App icon

Chosen by the owner on 10 November 2026 from several drafts: a red location
pin holding a white double-decker, on a dark map with the river, the bridge
and a red route running under the pin's tip.

- **Source:** `tools/icon/make_icon.py` writes the SVG sources and 1024 px
  PNGs to `assets/icons/` (`app_icon`, `app_icon_background`,
  `app_icon_foreground`, `app_icon_monochrome`). Edit the script, not the
  files. It renders with Microsoft Edge in headless mode and checks the sizes
  and transparency of what it writes.
- **Platform icons:** `flutter_launcher_icons` (dev dependency, configured at
  the end of `pubspec.yaml`) generates the Android mipmaps, the adaptive and
  themed (Android 13+) icon layers, and the iOS `AppIcon.appiconset`. Run
  `dart run flutter_launcher_icons` after changing the artwork.
- **Adaptive icon:** the layers are pre-scaled to 70% so the 72 dp area a
  launcher shows matches the full icon and the pin stays inside the 66 dp
  safe circle. The tool's default 16% foreground inset is turned off,
  because it would shrink the pin off the route in the background layer.
- **Recoloured to Teal Mint on 11 November 2026** (owner's choice "A" from
  mock-ups): mint pin (`#7FE0CB` → `#0A7563`), orange route (`#F2994A`,
  route 01's colour), on the app's slate map. Colours are the `C` dict in
  `tools/icon/make_icon.py`. The website was switched to Teal Mint at the
  same time (`website/src/css/styles.css`: `--brand`, `--route`).
- **Pin enlarged on 11 November 2026** at the owner's request: head radius
  280 → 320 (about 14% bigger, 62% of the icon's width), with the route
  moved down to stay under the tip. The adaptive layers are now centred on
  the pin rather than the canvas, which is what lets the bigger pin still fit
  the safe circle. The website's favicon, icons and link preview were
  regenerated from it.
- **iOS:** all 21 icon sizes are opaque (no alpha channel), as the App Store
  requires.
- `assets/icons/` is not listed under `flutter: assets`, so the source art is
  not bundled into the app.
- The web build still has Flutter's default icons (not requested).

## Marketing website (11 November 2026)

A static download and marketing site in `website/`, separate from the app.
Details: `website/README.md`.

- One page in plain HTML, CSS and JavaScript: a hero that fills the first
  screen, facts, features marked Available or In testing, how tracking
  works, real screenshots, roadmap, download, open source and an
  English/Bangla FAQ. Dark and light themes, phone-first layout, animations
  that respect "reduce motion".
- **Downloads come from GitHub Releases**: version, date, size, SHA-256,
  download count and stars are read live from the GitHub API. With no
  repository set in `website/site.config.json` the page says "coming soon"
  and shows no numbers.
- SEO: title, description, Open Graph image, JSON-LD (website, app, FAQ),
  sitemap, robots.txt.
- `.github/workflows/website.yml` publishes it with GitHub Pages once the
  repository exists.
- Screenshots are real, taken from the web build by
  `website/tools/capture_screens.mjs`.
- Checked in Edge at 1280 px and 390 px, dark and light: no horizontal
  scrolling, no console errors. Not yet checked on a real phone or in
  Firefox or Safari.

## Verification

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | 530 tests pass |
| Live tracking, passenger side | Checked in the web preview against the local emulators with a test position: the bus list showed "1 bus live", and a green marker with the bus number appeared on the map and moved when the position changed |
| Driver mode | App tests and rule tests only. **Not run on a phone: no real trip, no background check, no real GPS** |
| Tracking rules on the live project | Deployed. Without signing in, positions and trips can be read and nothing can be written; `admins` and `busDrivers` cannot be read |
| Managing the schedule | Tried end to end in the web preview against the local emulators, as a test admin: copied the 11 built-in timetables into the database (all 11 stored correctly), opened route 01, changed a departure from 8:30 to 8:40 AM, saved, and saw 8:40 AM on the passengers' schedule. **Not tried on the phone or against the live project** |
| Copy and paste coordinates | Widget tests and parser tests only. **The map actually moving to a pasted position has not been seen on a real map yet** |
| Managing stops | Tried end to end in the web preview against the local emulators, signed in as a test admin: opened a suggestion, dragged the map (the coordinates changed), saved, renamed, saw it on the passengers' Stops tab, deleted it. A write without signing in was refused. **Not tried on the phone or against the live project, which has no admin yet** |
| Security rule tests (emulators) | 86 pass |
| Official schedule | Tests read the shipped file: all groups, routes and 101 departures present, times in order. Seen working in the web preview (groups, routes, Bangla text). Not yet looked at on the phone |
| Public reading on the live project | Checked without signing in: routes, stops, buses, announcements, live positions and active trips can be read; profiles, trips and every write are refused |
| Cloud Functions | Compile. Not deployed, not run |
| Google sign-in | Worked on the phone against the live project on 10 November 2026: the owner signed in and the app created their profile. The live project is confirmed to have Google on and email and password off |
| First admin | The owner's account was made an admin with `tools/dev/set_user_role.js`. **Manage stops has not been tried on the phone yet** |
| Android release build with Firebase | Builds (41.6 MB, arm64), installs and starts on the phone. **The Profile tab's account section has not been looked at on the phone** |
| Android phone, online | Map draws at zoom 10 to 18 and at all eight coverage edges (feature counts in OFFLINE_MAP.md). That run ended with the disposal bug; the offline run below passed end to end with the fix |
| Android phone, airplane mode | **Passed.** Full sweep (zoom 10 to 18, eight coverage edges) on a fresh install with no internet, counts identical to online; release build also opens offline after a fresh install. Details in OFFLINE_MAP.md |
| Android phone, after a restart | Passed, checked by hand by the owner (airplane mode on) |
| Map management on the phone | Check map, Remove and Install map all worked in the release build |
| Offline label on the phone | Not checked on the device; covered by widget tests |
| Release build size | 35.7 MB (arm64) with map package version 3; it was 42.9 MB with version 2 |
| Map package update on the phone | Version 1 was replaced by version 2 on first launch of the new build |
| Map edges on the phone | North, south-east and west edges checked on screenshots: no straight cut-off |
| Device sweep with version 2, online | Passed end to end |
| Device sweep with version 2, airplane mode | Not repeated. Version 1 passed offline; version 2 uses the same code path with a different file |
| Bangla labels on the phone | Two Bangla-only names with simple vowel signs drew correctly. Names with conjuncts or reordered vowel signs have not been seen yet |
| ETA | Unit tests and widget tests with sample buses only |
| Routes, stops and selection | Checked in the web preview and on the phone with the demo route: lists, route framing, stop zoom and ring, map taps (map taps in the preview only) |
| Bus list and bus details | Widget tests only, with sample buses and a fixed clock |
| Web preview | Map renders from the bundled archive in light and dark; zoom in to buildings and place names; zoom out stops at 10; University button returns to campus; theme switch swaps the map style; sheet drags up and lists the demo route; phone-size layout checked |
| Android builds | Debug, profile and release build with JDK 25 and run on the phone |
| iOS build | Not possible on this machine; untested |
| My location on a real device | Untested. The permission and error paths are covered by widget tests with a fake location service |

A bug found by the tests and fixed: the installer deleted its own fresh copy
when the storage path used mixed separators. It now compares folder names.

## Package compatibility findings

All packages resolve together on Flutter 3.47.2 / Dart 3.13.2.

| Package | Version | Notes |
|---|---|---|
| `flutter_riverpod` | 3.5.0 | |
| `go_router` | 18.1.4 | |
| `maplibre_gl` | 0.28.0 | MapLibre Native Android 13.7.1, iOS 7.0.0. minSdk 24, iOS 15.5+. Needs JDK 21+ to build. A style change is applied with `controller.setStyle`; changing the widget's `styleString` does nothing after creation |
| `geolocator` | 14.1.2 | |
| `path_provider` | 2.1.6 | |
| `pointer_interceptor` | 0.10.1 | Web preview only: stops the map reacting to gestures on widgets drawn over it. Does nothing on Android and iOS |
| `firebase_core` | 5.1.0 | Prints a Kotlin Gradle Plugin deprecation warning. Harmless today |
| `firebase_auth` | 7.0.1 | Sign-in |
| `google_sign_in` | 7.2.0 | The Google account chooser on Android and iOS. On Android it reads its client id from `google-services.json` |
| `cloud_firestore` | 7.1.0 | User profiles so far |
| `shared_preferences` | 2.5.6 | |
| `connectivity_plus` | 7.3.1 | Reports whether a network is connected, not whether the internet is reachable |
| `crypto` | 3.0.8 | SHA-256 for the map integrity check |
| `integration_test` | SDK | On-device map test |

Checked and compatible, to be added when first used: `firebase_database`
13.0.1, `cloud_functions` 7.0.1, `firebase_messaging` 17.0.1,
`firebase_app_check` 0.5.1.

Backend tooling: Firebase CLI, Node 22 for the functions
(`firebase-functions` 6, `firebase-admin` 13), and
`@firebase/rules-unit-testing` for the rule tests.

## Architecture decisions

- **`maplibre_gl` over the `maplibre` package.** The MapLibre organisation's
  own plugin, with the offline, MBTiles and PMTiles features this app needs.
- **Map data from a Protomaps extract, not Planetiler.** This changed from the
  Phase 1 recommendation because Planetiler's inputs could not be downloaded
  on this network. Same OpenStreetMap data and licence. Reasons and
  trade-offs: OFFLINE_MAP.md.
- **Bundle the map package** rather than download it: it is about 15 MB.
- **Copy the package to app storage on Android and iOS.** MapLibre Native
  cannot read inside the Flutter asset bundle, and `file://` URLs behave the
  same on both platforms.
- **Styles are generated files.** Edit `tools/map/build_styles.py`, not the
  JSON.
- **No sprite.** Points of interest are a coloured dot and a label, so there
  are no icon files to keep in sync or to fail offline. Icons can be added
  later.
- **The app draws its own attribution label** so the credit stays visible
  above the bottom sheet.
- **Labels prefer English names**, falling back to the local name.
- **System fonts for the app UI**, not downloaded fonts.
- **Firebase is optional at startup.**
- **Sign-in is optional.** The map and the bundled routes work signed out;
  live bus data will need an account, because the rules require one.
- **Roles live in the Firestore profile, not in custom claims.** The rules
  read the profile, so a role change takes effect at once and needs no Cloud
  Function. The cost is one extra document read per rule check.
- **Trips are started only by a Cloud Function**, which picks the driver's
  bus and route on the server. The phone never chooses them.
- **Everything Firebase is in `asia-southeast1`** (Singapore).
- **Web is a preview target only.**
- **Git and GitHub** (11 November 2026): public repository
  https://github.com/Yeamin-Talukder/Barishal-University-Bus-Tracking-App
  (MIT). The website is published from `website/` with GitHub Pages at
  https://yeamin-talukder.github.io/Barishal-University-Bus-Tracking-App/.
  The project's own Firebase config stays off GitHub: `google-services.json`
  and `GoogleService-Info.plist` are ignored, and `lib/firebase_options.dart`
  and `firebase.json` are committed as public versions (a placeholder, and
  without the support email) while the real ones stay on this PC through
  `git update-index --skip-worktree`. Undo that flag before deliberately
  committing a change to either file.

## Current issues

1. **Nothing has run on iOS.** The offline map, the installer and the map
   itself are unproven there until a Mac is available.
2. **Android build needs JDK 21 or newer.** Flutter here is configured with
   JDK 17. To fix permanently:
   `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"`.
   This is a machine-wide setting, so it was not changed for you.
3. **Bangla-only place names may not be shaped correctly** by MapLibre. To be
   checked on a device.
4. **Detail above zoom 15 is overzoomed**, because the tile source stops at
   zoom 15. See OFFLINE_MAP.md.
5. **Kotlin incremental compilation is off** in `android/gradle.properties`
   because the project (`W:`) and pub cache (`C:`) are on different drives.
6. **Drive `C:` is nearly full** (about 1.2 GB free, and it has dipped to
   0.6 GB during builds). Gradle's cache there is about 13 GB and the npm
   cache about 3.9 GB. Builds may start failing if it fills.
7. **Application IDs** are `bd.ac.bu.bu_bus_tracker` (Android) and
   `bd.ac.bu.buBusTracker` (iOS). They are now registered in the Firebase
   project, so changing them means registering new apps there.
8. **The route paths are a routing service's best guess** between the
   owner's stops, not recorded paths. They need the owner's eye. Routes 04 to
   08 are not drawn at all.
9. **Bus positions do not exist yet.** Registered buses now appear in the
   app's bus list, all as "No position received yet", until real-time
   tracking is built (Phase 7).
10. **The debug APK is large (about 190 MB)**; the release build is 41.6 MB.
11. **The test phone is nearly full** (about 0.5 GB free of 110 GB). Android
    refused to install the debug build for lack of space, so device tests use
    profile and release builds. Freeing a few gigabytes would avoid this.
12. **Bangla shaping is only partly checked.** Simple Bangla-only names draw
    correctly on the phone. Names with conjuncts or with vowel signs that sit
    before their consonant have not been checked.
13. **The on-device test must not be closed while it runs.** It now ignores
    touches and shows a notice, but closing the app, unplugging the cable or
    changing airplane mode still ends the run. It takes about a minute and a
    half. The runner now taps the screen to stop it timing out, which had
    been ending runs on a phone running on battery.
14. **Newer map data can only arrive with an app update.** There is nowhere
    to host a map package yet.
15. **Cloud Functions cannot be deployed on the Spark plan.** Until the
    project is on Blaze, trips cannot start, so driver mode cannot work.
16. **Bus data is public to read.** Nobody can be blocked individually, and
    a script could use up the free plan's daily read allowance. App Check is
    the planned protection.
17. **Anyone with a Google account can sign in.** Such an account can do
    nothing the public cannot, until an admin makes it a driver or admin.
19. **Release builds are signed with this computer's debug key**, and Google
    sign-in is tied to that key. A proper release key is needed before
    publishing.
20. **iOS needs more setup for Google sign-in** (a URL scheme and
    `GoogleService-Info.plist`), which can only be done on a Mac.
18. **Drive `C:` filled up completely during this work** (0.02 GB free), which
    made the test runner crash with "Out of memory". Tests and builds were
    then run with `TEMP` and `TMP` pointed at `build/tmp` on drive `W:`.
    Space on `C:` has to be freed by the owner.

## Manual setup needed from you

- Point Flutter at JDK 21+ (issue 2).
- A Mac with Xcode for any iOS build or test, and to generate
  `GoogleService-Info.plist`.
- **Decide on the Blaze plan** for Cloud Functions (FIREBASE_SETUP.md).
- A proper release signing key before publishing; Google sign-in is tied to
  the key that signs the app (FIREBASE_SETUP.md).
- Positions for the official stops, and the roads each route follows, so the
  routes can be drawn on the map (`docs/TRANSPORT_DATA_FORMAT.md`).
- The days the schedule applies on, and any routes missing from it.
- Free space on drive `C:`.

## Next tasks (rest of Phase 5)

0. Admin editors still to build: announcements.
1. Deploy `startTrip` and `endTrip` once the project is on Blaze, and test
   them on the emulator first.
2. Firestore repositories for buses, routes, stops and announcements, falling
   back to the bundled files when signed out or offline.
3. A role-assignment path for admins that does not need the console.
4. App Check (FIREBASE_SETUP.md lists the steps).
5. Look at the Profile tab on the phone, and try sign-in there against the
   real project.

Still possible without further Firebase work:

- Check Bangla names with conjuncts on the phone.
- Repeat the airplane-mode sweep with map package version 2.
- Repeat the device tests on iOS when a Mac is available.
