// Drives a clearly labelled TEST bus along a saved route in the project's
// live database, so the passenger side of the app can be watched on one
// phone. It is not a real bus and these are not real GPS positions: the
// bus is named "TEST (not a real bus)", and the bus, its trip and its
// position are all removed when the run ends.
//
// Uses the Firebase CLI's own signed-in session (project owner).
//
//   node tools/dev/simulate_test_trip.js <project> <database url> [route] [minutes]
const path = require("path");

const lib = path.join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib");
const { Command } = require(path.join(lib, "command"));
const { requireAuth } = require(path.join(lib, "requireAuth"));
const { Client } = require(path.join(lib, "apiv2"));

const [project, databaseUrl, routeId = "01", minutesText = "6"] = process.argv.slice(2);
if (!project || !databaseUrl) {
  console.error("Usage: simulate_test_trip.js <project> <database url> [route] [minutes]");
  process.exit(2);
}
const BUS = "test-bus";
const SPEED = 11; // metres per second, about 40 km/h
const STEP_SECONDS = 3;
const runSeconds = Number(minutesText) * 60;

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

async function cleanUp() {
  await database.put(`/activeTrips/${BUS}.json`, null).catch(() => {});
  await database.put(`/liveLocations/${BUS}.json`, null).catch(() => {});
  await firestore.delete(`${documents}/buses/${BUS}`).catch(() => {});
}

const command = new Command("internal:simulate-test-trip")
  .before(requireAuth)
  .action(async () => {
    const route = (await firestore.get(`${documents}/routes/${routeId}`)).body;
    const points = route.fields.path.arrayValue.values.map((v) => [
      v.mapValue.fields.latitude.doubleValue,
      v.mapValue.fields.longitude.doubleValue,
    ]);

    await firestore.patch(`${documents}/buses/${BUS}`, {
      fields: {
        busNumber: { stringValue: "TEST" },
        name: { stringValue: "TEST (not a real bus)" },
        routeId: { stringValue: routeId },
        isActive: { booleanValue: true },
      },
    });
    await database.put(`/activeTrips/${BUS}.json`, {
      tripId: "test-trip",
      driverUid: "test",
      status: "active",
      routeId,
      startedAt: { ".sv": "timestamp" },
    });
    console.log(`TEST bus started on route ${routeId} for ${minutesText} minutes`);

    let segment = 0;
    let along = 0; // metres into the current segment
    let sent = 0;
    try {
      for (let elapsed = 0; elapsed < runSeconds && segment < points.length - 1; elapsed += STEP_SECONDS) {
        let advance = SPEED * STEP_SECONDS;
        while (segment < points.length - 1) {
          const length = meters(points[segment], points[segment + 1]);
          if (along + advance < length) {
            along += advance;
            break;
          }
          advance -= length - along;
          along = 0;
          segment += 1;
        }
        if (segment >= points.length - 1) break;
        const a = points[segment];
        const b = points[segment + 1];
        const f = along / Math.max(meters(a, b), 0.01);
        await database.put(`/liveLocations/${BUS}.json`, {
          tripId: "test-trip",
          driverUid: "test",
          latitude: a[0] + (b[0] - a[0]) * f,
          longitude: a[1] + (b[1] - a[1]) * f,
          heading: bearing(a, b),
          speed: SPEED,
          accuracy: 8,
          updatedAt: { ".sv": "timestamp" },
        });
        sent += 1;
        if (sent % 20 === 0) console.log(`${sent} positions sent`);
        await sleep(STEP_SECONDS * 1000);
      }
    } finally {
      await cleanUp();
    }
    return `done: ${sent} positions sent, TEST bus, trip and position removed`;
  });

process.on("SIGINT", () => cleanUp().finally(() => process.exit(1)));

command
  .runner()({ project, nonInteractive: true })
  .then((result) => console.log(result))
  .catch((error) => {
    console.error("FAILED:", error.message || error);
    return cleanUp().finally(() => {
      process.exitCode = 1;
    });
  });
