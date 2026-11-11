// Drives six clearly labelled TEST buses in the project's live database, so
// the passenger side of the app can be watched with several buses at once:
// on each of routes 01, 02 and 03, one bus from the route's far end to the
// University and one from the University to the far end. Each has its own
// speed and starts a little after the one before.
//
// They are not real buses and these are not real GPS positions: every bus
// is named "TEST n (not a real bus)", and the buses, their trips and their
// positions are all removed when the run ends.
//
// Uses the Firebase CLI's own signed-in session (project owner).
//
//   node tools/dev/simulate_test_fleet.js <project> <database url> [minutes]
const path = require("path");

const lib = path.join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib");
const { Command } = require(path.join(lib, "command"));
const { requireAuth } = require(path.join(lib, "requireAuth"));
const { Client } = require(path.join(lib, "apiv2"));

const [project, databaseUrl, minutesText = "8"] = process.argv.slice(2);
if (!project || !databaseUrl) {
  console.error("Usage: simulate_test_fleet.js <project> <database url> [minutes]");
  process.exit(2);
}
const STEP_SECONDS = 3;
const runSeconds = Number(minutesText) * 60;

// The saved route paths end at the University, so "to the University" is
// the path as saved and "from the University" is the path backwards.
// Speeds are in metres per second (29 to 50 km/h).
const FLEET = [
  { n: 1, routeId: "01", fromUniversity: true, speed: 11, startAfter: 0 },
  { n: 2, routeId: "02", fromUniversity: true, speed: 8, startAfter: 8 },
  { n: 3, routeId: "03", fromUniversity: true, speed: 13, startAfter: 16 },
  { n: 4, routeId: "01", fromUniversity: false, speed: 9, startAfter: 24 },
  { n: 5, routeId: "02", fromUniversity: false, speed: 14, startAfter: 32 },
  { n: 6, routeId: "03", fromUniversity: false, speed: 10, startAfter: 40 },
];
const busId = (bus) => `test-bus-${bus.n}`;

const firestore = new Client({ urlPrefix: "https://firestore.googleapis.com", apiVersion: "v1" });
const database = new Client({ urlPrefix: databaseUrl.replace(/\/$/, "") });
const documents = `/projects/${project}/databases/(default)/documents`;

const rad = (d) => (d * Math.PI) / 180;
function meters(a, b) {
  const dLat = rad(b[0] - a[0]);
  const dLon = rad(b[1] - a[1]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2;
  return 6371008.8 * 2 * Math.asin(Math.sqrt(h));
}
function bearing(a, b) {
  const y = Math.sin(rad(b[1] - a[1])) * Math.cos(rad(b[0]));
  const x = Math.cos(rad(a[0])) * Math.sin(rad(b[0])) - Math.sin(rad(a[0])) * Math.cos(rad(b[0])) * Math.cos(rad(b[1] - a[1]));
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function remove(bus) {
  const id = busId(bus);
  await database.put(`/activeTrips/${id}.json`, null).catch(() => {});
  await database.put(`/liveLocations/${id}.json`, null).catch(() => {});
  await firestore.delete(`${documents}/buses/${id}`).catch(() => {});
}
const cleanUp = () => Promise.all(FLEET.map(remove));

async function start(bus) {
  const id = busId(bus);
  await firestore.patch(`${documents}/buses/${id}`, {
    fields: {
      busNumber: { stringValue: `TEST ${bus.n}` },
      name: { stringValue: `TEST ${bus.n} (not a real bus)` },
      routeId: { stringValue: bus.routeId },
      isActive: { booleanValue: true },
    },
  });
  await database.put(`/activeTrips/${id}.json`, {
    tripId: `test-trip-${bus.n}`,
    driverUid: "test",
    status: "active",
    routeId: bus.routeId,
    startedAt: { ".sv": "timestamp" },
  });
  bus.started = true;
  const way = bus.fromUniversity ? "from the University" : "to the University";
  console.log(`TEST ${bus.n} started on route ${bus.routeId} ${way} at ${Math.round(bus.speed * 3.6)} km/h`);
}

// Moves the bus one step along its path and sends where it is now.
// Returns false once it has reached the end.
async function step(bus) {
  const points = bus.points;
  let advance = bus.speed * STEP_SECONDS;
  while (bus.segment < points.length - 1) {
    const length = meters(points[bus.segment], points[bus.segment + 1]);
    if (bus.along + advance < length) {
      bus.along += advance;
      break;
    }
    advance -= length - bus.along;
    bus.along = 0;
    bus.segment += 1;
  }
  if (bus.segment >= points.length - 1) return false;
  const a = points[bus.segment];
  const b = points[bus.segment + 1];
  const f = bus.along / Math.max(meters(a, b), 0.01);
  await database.put(`/liveLocations/${busId(bus)}.json`, {
    tripId: `test-trip-${bus.n}`,
    driverUid: "test",
    latitude: a[0] + (b[0] - a[0]) * f,
    longitude: a[1] + (b[1] - a[1]) * f,
    heading: bearing(a, b),
    speed: bus.speed,
    accuracy: 8,
    updatedAt: { ".sv": "timestamp" },
  });
  bus.sent += 1;
  return true;
}

const command = new Command("internal:simulate-test-fleet")
  .before(requireAuth)
  .action(async () => {
    const paths = {};
    for (const routeId of new Set(FLEET.map((bus) => bus.routeId))) {
      const route = (await firestore.get(`${documents}/routes/${routeId}`)).body;
      paths[routeId] = route.fields.path.arrayValue.values.map((v) => [
        v.mapValue.fields.latitude.doubleValue,
        v.mapValue.fields.longitude.doubleValue,
      ]);
    }
    for (const bus of FLEET) {
      bus.points = bus.fromUniversity ? [...paths[bus.routeId]].reverse() : paths[bus.routeId];
      bus.segment = 0;
      bus.along = 0;
      bus.sent = 0;
      bus.started = false;
      bus.finished = false;
    }
    console.log(`Six TEST buses, for ${minutesText} minutes`);

    try {
      for (let elapsed = 0; elapsed < runSeconds; elapsed += STEP_SECONDS) {
        const tickStarted = Date.now();
        await Promise.all(
          FLEET.map(async (bus) => {
            if (bus.finished || elapsed < bus.startAfter) return;
            if (!bus.started) await start(bus);
            if (!(await step(bus))) {
              // It has arrived: the trip ends, as a driver would end it.
              bus.finished = true;
              await remove(bus);
              console.log(`TEST ${bus.n} arrived and was removed`);
            }
          }),
        );
        if (FLEET.every((bus) => bus.finished)) break;
        if (elapsed > 0 && elapsed % 60 === 0) {
          console.log(`${elapsed / 60} min: ${FLEET.map((bus) => bus.sent).join(", ")} positions sent`);
        }
        // Keep the three-second rhythm whatever the writes took.
        await sleep(Math.max(0, STEP_SECONDS * 1000 - (Date.now() - tickStarted)));
      }
    } finally {
      await cleanUp();
    }
    const total = FLEET.reduce((sum, bus) => sum + bus.sent, 0);
    return `done: ${total} positions sent, all six TEST buses, their trips and positions removed`;
  });

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => cleanUp().finally(() => process.exit(1)));
}

command
  .runner()({ project, nonInteractive: true })
  .then((result) => console.log(result))
  .catch((error) => {
    console.error("FAILED:", error.message || error);
    return cleanUp().finally(() => {
      process.exitCode = 1;
    });
  });
