// Tests for firebase/database.rules.json. Run from the project root with:
//
//   firebase emulators:exec --only firestore,database "npm --prefix firebase/test test"
//
// The project runs without Cloud Functions, so these rules are what decides
// who may start a trip and publish a bus's position:
//
//   admins/{uid}        who is an admin (mirrors the Firestore profiles)
//   busDrivers/{busId}  which driver a bus is assigned to (set by an admin)
//   activeTrips/{busId} written by that bus's assigned driver
//   liveLocations/{busId} written by the driver of the active trip

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { get, ref, remove, serverTimestamp, set, update } from "firebase/database";

let env;

const admin = "admin1";
const otherAdmin = "admin2";
const driver = "driver1";
const otherDriver = "driver2";
const student = "student1";

const db = (uid) => env.authenticatedContext(uid).database();
const anonymous = () => env.unauthenticatedContext().database();

const trip = (uid, overrides = {}) => ({
  tripId: "trip1",
  driverUid: uid,
  status: "active",
  startedAt: serverTimestamp(),
  ...overrides,
});

const location = (overrides = {}) => ({
  tripId: "trip1",
  driverUid: driver,
  latitude: 22.659967,
  longitude: 90.363381,
  heading: 90,
  speed: 8.5,
  accuracy: 6,
  updatedAt: serverTimestamp(),
  ...overrides,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-bu-bus-tracker",
    database: {
      rules: readFileSync(
        new URL("../database.rules.json", import.meta.url),
        "utf8",
      ),
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearDatabase();
  await env.withSecurityRulesDisabled(async (context) => {
    const root = context.database();
    await set(ref(root, "admins"), { [admin]: true, [otherAdmin]: true });
    await set(ref(root, "busDrivers"), {
      bus1: driver, // on a trip
      bus2: otherDriver, // on a trip
      bus3: driver, // assigned, no trip
    });
    await set(ref(root, "activeTrips/bus1"), {
      tripId: "trip1",
      driverUid: driver,
      status: "active",
      startedAt: 1,
    });
    await set(ref(root, "activeTrips/bus2"), {
      tripId: "trip2",
      driverUid: otherDriver,
      status: "active",
      startedAt: 1,
    });
  });
});

describe("reading", () => {
  test("anyone can read bus positions and active trips without signing in", async () => {
    await assertSucceeds(get(ref(anonymous(), "liveLocations")));
    await assertSucceeds(get(ref(anonymous(), "liveLocations/bus1")));
    await assertSucceeds(get(ref(anonymous(), "activeTrips")));
    await assertSucceeds(get(ref(anonymous(), "activeTrips/bus1")));
  });

  test("the rest of the database is closed", async () => {
    for (const reader of [anonymous(), db(student), db(driver)]) {
      await assertFails(get(ref(reader, "/")));
      await assertFails(get(ref(reader, "anythingElse")));
    }
  });

  test("bus assignments are for signed-in people only", async () => {
    await assertSucceeds(get(ref(db(driver), "busDrivers")));
    await assertFails(get(ref(anonymous(), "busDrivers")));
  });

  test("a person can see whether they are an admin, not whether others are", async () => {
    await assertSucceeds(get(ref(db(student), `admins/${student}`)));
    await assertFails(get(ref(db(student), `admins/${admin}`)));
    await assertFails(get(ref(db(student), "admins")));
    await assertSucceeds(get(ref(db(admin), `admins/${otherAdmin}`)));
    await assertFails(get(ref(anonymous(), `admins/${admin}`)));
  });

  test("nothing can be written without signing in", async () => {
    await assertFails(set(ref(anonymous(), "activeTrips/bus9"), trip("nobody")));
    await assertFails(remove(ref(anonymous(), "activeTrips/bus1")));
    await assertFails(remove(ref(anonymous(), "liveLocations/bus1")));
    await assertFails(set(ref(anonymous(), "busDrivers/bus1"), "nobody"));
    await assertFails(set(ref(anonymous(), "admins/nobody"), true));
    await assertFails(set(ref(anonymous(), "anythingElse"), { a: 1 }));
  });
});

describe("who is an admin", () => {
  test("an admin can make someone else an admin, and take it away", async () => {
    await assertSucceeds(set(ref(db(admin), `admins/${student}`), true));
    await assertSucceeds(remove(ref(db(admin), `admins/${otherAdmin}`)));
  });

  test("nobody can make themselves an admin", async () => {
    for (const uid of [student, driver]) {
      await assertFails(set(ref(db(uid), `admins/${uid}`), true));
      await assertFails(update(ref(db(uid), "admins"), { [uid]: true }));
    }
  });

  test("someone who is not an admin cannot change the list", async () => {
    await assertFails(set(ref(db(driver), `admins/${student}`), true));
    await assertFails(remove(ref(db(driver), `admins/${admin}`)));
  });

  test("an admin cannot remove themselves, so one always remains", async () => {
    await assertFails(remove(ref(db(admin), `admins/${admin}`)));
  });

  test("the entry can only be true", async () => {
    await assertFails(set(ref(db(admin), `admins/${student}`), false));
    await assertFails(set(ref(db(admin), `admins/${student}`), "yes"));
  });
});

describe("assigning a driver to a bus", () => {
  test("an admin can assign, reassign and unassign", async () => {
    await assertSucceeds(set(ref(db(admin), "busDrivers/bus9"), driver));
    await assertSucceeds(set(ref(db(admin), "busDrivers/bus1"), otherDriver));
    await assertSucceeds(remove(ref(db(admin), "busDrivers/bus3")));
  });

  test("nobody else can, not even for themselves", async () => {
    for (const uid of [driver, student]) {
      await assertFails(set(ref(db(uid), "busDrivers/bus9"), uid));
      await assertFails(set(ref(db(uid), "busDrivers/bus2"), uid));
      await assertFails(remove(ref(db(uid), "busDrivers/bus2")));
    }
  });

  test("the value must be a driver's id", async () => {
    await assertFails(set(ref(db(admin), "busDrivers/bus9"), ""));
    await assertFails(set(ref(db(admin), "busDrivers/bus9"), 42));
    await assertFails(set(ref(db(admin), "busDrivers/bus9"), { uid: driver }));
  });
});

describe("starting and ending a trip", () => {
  test("the bus's assigned driver can start a trip", async () => {
    await assertSucceeds(set(ref(db(driver), "activeTrips/bus3"), trip(driver)));
    await assertSucceeds(
      set(ref(db(driver), "activeTrips/bus3"), trip(driver, { routeId: "01" })),
    );
  });

  test("a driver cannot start a trip on a bus that is not theirs", async () => {
    await assertFails(set(ref(db(driver), "activeTrips/bus2"), trip(driver)));
    await assertFails(set(ref(db(driver), "activeTrips/bus404"), trip(driver)));
  });

  test("a student cannot start a trip", async () => {
    await assertFails(set(ref(db(student), "activeTrips/bus3"), trip(student)));
  });

  test("an admin cannot start a trip, only the driver can", async () => {
    await assertFails(set(ref(db(admin), "activeTrips/bus3"), trip(admin)));
    await assertFails(set(ref(db(admin), "activeTrips/bus3"), trip(driver)));
  });

  test("a trip cannot be started in someone else's name", async () => {
    await assertFails(
      set(ref(db(driver), "activeTrips/bus3"), trip(otherDriver)),
    );
  });

  test("a trip must be well formed", async () => {
    for (const bad of [
      { status: "ended" },
      { status: "paused" },
      { startedAt: 12345 },
      { tripId: "" },
      { tripId: "x".repeat(65) },
      { note: "extra" },
      { routeId: 7 },
    ]) {
      await assertFails(
        set(ref(db(driver), "activeTrips/bus3"), trip(driver, bad)),
      );
    }
    for (const field of ["tripId", "driverUid", "status", "startedAt"]) {
      const incomplete = trip(driver);
      delete incomplete[field];
      await assertFails(set(ref(db(driver), "activeTrips/bus3"), incomplete));
    }
  });

  test("the driver can end their trip", async () => {
    await assertSucceeds(remove(ref(db(driver), "activeTrips/bus1")));
  });

  test("the driver can end the trip and clear the position in one step", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
    await assertSucceeds(
      update(ref(db(driver)), {
        "activeTrips/bus1": null,
        "liveLocations/bus1": null,
      }),
    );
  });

  test("another driver or a student cannot end it", async () => {
    await assertFails(remove(ref(db(otherDriver), "activeTrips/bus1")));
    await assertFails(remove(ref(db(student), "activeTrips/bus1")));
  });

  test("an admin can end any trip and clear its position", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
    await assertSucceeds(
      update(ref(db(admin)), {
        "activeTrips/bus1": null,
        "liveLocations/bus1": null,
      }),
    );
  });

  test("a driver taken off a bus can no longer start a trip on it", async () => {
    await assertSucceeds(remove(ref(db(admin), "busDrivers/bus3")));
    await assertFails(set(ref(db(driver), "activeTrips/bus3"), trip(driver)));
  });
});

describe("publishing a bus position", () => {
  test("the driver of the active trip can", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
  });

  test("heading, speed and accuracy are optional", async () => {
    const { heading, speed, accuracy, ...minimal } = location();
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), minimal));
  });

  test("a student cannot", async () => {
    await assertFails(
      set(ref(db(student), "liveLocations/bus1"), location({ driverUid: student })),
    );
  });

  test("an admin cannot publish a position", async () => {
    await assertFails(
      set(ref(db(admin), "liveLocations/bus1"), location({ driverUid: admin })),
    );
    await assertFails(set(ref(db(admin), "liveLocations/bus1"), location()));
  });

  test("a driver cannot publish for another driver's bus", async () => {
    await assertFails(
      set(ref(db(driver), "liveLocations/bus2"), location({ tripId: "trip2" })),
    );
  });

  test("a driver cannot pose as another driver", async () => {
    await assertFails(
      set(ref(db(driver), "liveLocations/bus1"), location({ driverUid: otherDriver })),
    );
    await assertFails(
      set(ref(db(otherDriver), "liveLocations/bus1"), location({ driverUid: driver })),
    );
  });

  test("not for a bus with no trip", async () => {
    await assertFails(
      set(ref(db(driver), "liveLocations/bus3"), location({ tripId: "x" })),
    );
  });

  test("not once the driver has been taken off the bus, even mid-trip", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
    await assertSucceeds(remove(ref(db(admin), "busDrivers/bus1")));
    await sleep(1100);
    await assertFails(set(ref(db(driver), "liveLocations/bus1"), location()));
  });

  test("not with the wrong trip id", async () => {
    await assertFails(
      set(ref(db(driver), "liveLocations/bus1"), location({ tripId: "trip2" })),
    );
  });

  test("not with coordinates outside Bangladesh or not numbers", async () => {
    for (const bad of [
      { latitude: 51.5 },
      { latitude: -22.66 },
      { longitude: 0 },
      { longitude: 190 },
      { latitude: "22.66" },
    ]) {
      await assertFails(set(ref(db(driver), "liveLocations/bus1"), location(bad)));
    }
  });

  test("not with an impossible heading, speed or accuracy", async () => {
    for (const bad of [
      { heading: 400 },
      { heading: -1 },
      { speed: -3 },
      { speed: 300 },
      { accuracy: -1 },
    ]) {
      await assertFails(set(ref(db(driver), "liveLocations/bus1"), location(bad)));
    }
  });

  test("not with a time chosen by the phone", async () => {
    await assertFails(
      set(ref(db(driver), "liveLocations/bus1"), location({ updatedAt: Date.now() })),
    );
    await assertFails(
      set(ref(db(driver), "liveLocations/bus1"), location({ updatedAt: 0 })),
    );
  });

  test("not with missing required fields", async () => {
    for (const field of ["tripId", "driverUid", "latitude", "longitude", "updatedAt"]) {
      const incomplete = location();
      delete incomplete[field];
      await assertFails(set(ref(db(driver), "liveLocations/bus1"), incomplete));
    }
  });

  test("not with extra fields", async () => {
    await assertFails(
      set(ref(db(driver), "liveLocations/bus1"), location({ note: "hello" })),
    );
  });

  test("not more than once a second", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
    await assertFails(set(ref(db(driver), "liveLocations/bus1"), location()));

    await sleep(1100);
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
  });

  test("the driver can clear their own bus's position", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
    await assertSucceeds(remove(ref(db(driver), "liveLocations/bus1")));
  });

  test("another driver or a student cannot clear it", async () => {
    await assertSucceeds(set(ref(db(driver), "liveLocations/bus1"), location()));
    await assertFails(remove(ref(db(student), "liveLocations/bus1")));
    await assertFails(remove(ref(db(otherDriver), "liveLocations/bus1")));
  });
});
