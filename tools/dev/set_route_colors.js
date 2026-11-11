// Sets the colour of routes in the project's database. Only the `color`
// field of each named route is changed; paths, stops and names are left
// as they are.
//
// Uses the Firebase CLI's own signed-in session (project owner).
//
//   node tools/dev/set_route_colors.js <project> 01=#E53945 02=#72A9E8 ...
const path = require("path");

const lib = path.join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib");
const { Command } = require(path.join(lib, "command"));
const { requireAuth } = require(path.join(lib, "requireAuth"));
const { Client } = require(path.join(lib, "apiv2"));

const [project, ...pairs] = process.argv.slice(2);
const colors = pairs.map((pair) => pair.split("="));
if (!project || colors.length === 0 || colors.some(([id, hex]) => !id || !/^#[0-9A-Fa-f]{6}$/.test(hex || ""))) {
  console.error("Usage: set_route_colors.js <project> <route>=#RRGGBB ...");
  process.exit(2);
}

const firestore = new Client({ urlPrefix: "https://firestore.googleapis.com", apiVersion: "v1" });
const documents = `/projects/${project}/databases/(default)/documents`;

new Command("internal:set-route-colors")
  .before(requireAuth)
  .action(async () => {
    const lines = [];
    for (const [id, hex] of colors) {
      const doc = `${documents}/routes/${id}`;
      // Fails here, before anything is written, if the route does not exist.
      const before = (await firestore.get(doc)).body.fields.color?.stringValue;
      await firestore.patch(
        doc,
        { fields: { color: { stringValue: hex.toUpperCase() } } },
        { queryParams: { "updateMask.fieldPaths": "color", "currentDocument.exists": "true" } },
      );
      const after = (await firestore.get(doc)).body.fields;
      lines.push(
        `route ${id}: ${before} -> ${after.color.stringValue} ` +
          `(${after.path.arrayValue.values.length} path points, ${after.stopIds.arrayValue.values.length} stops kept)`,
      );
    }
    return lines.join("\n");
  })
  .runner()({ project, nonInteractive: true })
  .then((result) => console.log(result))
  .catch((error) => {
    console.error("FAILED:", error.message || error);
    process.exitCode = 1;
  });
