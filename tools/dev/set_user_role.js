// Lists the profiles in the project's `users` collection, or sets one
// profile's role. Uses the Firebase CLI's own signed-in session, so it acts
// as the project owner; the app itself can never do this.
//
//   node tools/dev/set_user_role.js <project>                    list
//   node tools/dev/set_user_role.js <project> <email> <role>     set role
//
// Roles: student (no special access), driver, admin.
const path = require("path");

const lib = path.join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib");
const { Command } = require(path.join(lib, "command"));
const { requireAuth } = require(path.join(lib, "requireAuth"));
const { Client } = require(path.join(lib, "apiv2"));

const [project, email, role] = process.argv.slice(2);
const ROLES = ["student", "driver", "admin"];
if (!project || (email && !ROLES.includes(role))) {
  console.error("Usage: set_user_role.js <project> [<email> <student|driver|admin>]");
  process.exit(2);
}

const client = new Client({
  urlPrefix: "https://firestore.googleapis.com",
  apiVersion: "v1",
});
const base = `/projects/${project}/databases/(default)/documents`;

const text = (doc, field) => doc.fields?.[field]?.stringValue ?? "";
const describe = (doc) =>
  `${text(doc, "email")} | ${text(doc, "name")} | role: ${text(doc, "role")} | ` +
  `active: ${doc.fields?.isActive?.booleanValue === true}`;

const command = new Command("internal:set-user-role")
  .before(requireAuth)
  .action(async () => {
    const listed = (await client.get(`${base}/users`, { queryParams: { pageSize: "100" } })).body;
    const profiles = listed.documents || [];
    if (!email) {
      return [`${profiles.length} profile(s)`, ...profiles.map(describe)].join("\n");
    }
    const matches = profiles.filter(
      (doc) => text(doc, "email").toLowerCase() === email.toLowerCase(),
    );
    if (matches.length !== 1) {
      throw new Error(`Expected one profile for that email, found ${matches.length}.`);
    }
    const name = matches[0].name.split("/documents")[1];
    const updated = (
      await client.patch(
        `${base}${name}`,
        { fields: { role: { stringValue: role } } },
        { queryParams: { "updateMask.fieldPaths": "role" } },
      )
    ).body;
    return "updated -> " + describe(updated);
  });

command
  .runner()({ project, nonInteractive: true })
  .then((result) => console.log(result))
  .catch((error) => {
    console.error("FAILED:", error.message || error);
    process.exitCode = 1;
  });
