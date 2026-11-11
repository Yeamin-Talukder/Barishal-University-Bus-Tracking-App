// Copies who is an admin, and who drives each bus, from Firestore to the
// Realtime Database, where the tracking rules need them.
//
// The app keeps the two in step by itself whenever an admin changes a bus or
// a person. This script is for the first set-up (the first admin has to be
// recorded from outside the app) and for repairing the copy if it is ever
// in doubt. It uses the Firebase CLI's own signed-in session, so it acts as
// the project owner. It prints counts, not people's details.
//
//   node tools/dev/sync_tracking_access.js <project> <database url>
const path = require("path");

const lib = path.join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib");
const { Command } = require(path.join(lib, "command"));
const { requireAuth } = require(path.join(lib, "requireAuth"));
const { Client } = require(path.join(lib, "apiv2"));

const [project, databaseUrl] = process.argv.slice(2);
if (!project || !databaseUrl) {
  console.error("Usage: sync_tracking_access.js <project> <database url>");
  process.exit(2);
}

const firestore = new Client({ urlPrefix: "https://firestore.googleapis.com", apiVersion: "v1" });
const database = new Client({ urlPrefix: databaseUrl.replace(/\/$/, "") });
const documents = `/projects/${project}/databases/(default)/documents`;

async function all(collection) {
  const found = [];
  let pageToken;
  do {
    const queryParams = { pageSize: "300" };
    if (pageToken) queryParams.pageToken = pageToken;
    const page = (await firestore.get(`${documents}/${collection}`, { queryParams })).body;
    found.push(...(page.documents || []));
    pageToken = page.nextPageToken;
  } while (pageToken);
  return found;
}

const id = (doc) => doc.name.split("/").pop();
const text = (doc, field) => doc.fields?.[field]?.stringValue ?? "";
const flag = (doc, field) => doc.fields?.[field]?.booleanValue === true;

const command = new Command("internal:sync-tracking-access")
  .before(requireAuth)
  .action(async () => {
    const admins = {};
    for (const user of await all("users")) {
      if (text(user, "role") === "admin" && flag(user, "isActive")) admins[id(user)] = true;
    }
    const busDrivers = {};
    for (const bus of await all("buses")) {
      const driver = text(bus, "driverUid");
      if (driver && flag(bus, "isActive")) busDrivers[id(bus)] = driver;
    }
    if (Object.keys(admins).length === 0) {
      throw new Error("No active admin in Firestore. Make one first.");
    }
    await database.put("/admins.json", admins);
    await database.put("/busDrivers.json", busDrivers);
    return `admins recorded: ${Object.keys(admins).length}, buses with a driver: ${Object.keys(busDrivers).length}`;
  });

command
  .runner()({ project, nonInteractive: true })
  .then((result) => console.log(result))
  .catch((error) => {
    console.error("FAILED:", error.message || error);
    process.exitCode = 1;
  });
