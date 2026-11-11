// Saves the routes in tools/data/routes_draft.json (written by
// tools/data/build_routes.py) to the project's `routes` collection, replacing
// routes with the same number. Uses the Firebase CLI's own signed-in
// session, so it acts as the project owner.
//
//   node tools/dev/upload_routes.js <project>
const fs = require("fs");
const path = require("path");

const lib = path.join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib");
const { Command } = require(path.join(lib, "command"));
const { requireAuth } = require(path.join(lib, "requireAuth"));
const { Client } = require(path.join(lib, "apiv2"));

const project = process.argv[2];
if (!project) {
  console.error("Usage: upload_routes.js <project>");
  process.exit(2);
}

const draft = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "data", "routes_draft.json"), "utf8"),
);
const client = new Client({ urlPrefix: "https://firestore.googleapis.com", apiVersion: "v1" });
const documents = `/projects/${project}/databases/(default)/documents`;

const text = (value) => ({ stringValue: value });
const fieldsOf = (route) => ({
  name: text(route.name),
  color: text(route.color),
  startLocation: text(route.start),
  endLocation: text(route.end),
  isActive: { booleanValue: true },
  stopIds: { arrayValue: { values: route.stopIds.map(text) } },
  path: {
    arrayValue: {
      values: route.path.map(([latitude, longitude]) => ({
        mapValue: {
          fields: {
            latitude: { doubleValue: latitude },
            longitude: { doubleValue: longitude },
          },
        },
      })),
    },
  },
});

const command = new Command("internal:upload-routes")
  .before(requireAuth)
  .action(async () => {
    const lines = [];
    for (const [number, route] of Object.entries(draft.routes)) {
      await client.patch(`${documents}/routes/${number}`, { fields: fieldsOf(route) });
      lines.push(
        `route ${number}: ${route.path.length} points, ${route.stopIds.length} stops, ` +
          `${(route.roadMeters / 1000).toFixed(2)} km`,
      );
    }
    return lines.join("\n");
  });

command
  .runner()({ project, nonInteractive: true })
  .then((result) => console.log(result))
  .catch((error) => {
    console.error("FAILED:", error.message || error);
    process.exitCode = 1;
  });
