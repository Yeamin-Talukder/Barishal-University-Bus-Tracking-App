// Tests for firebase/firestore.rules. Run from the project root with:
//
//   firebase emulators:exec --only firestore,database "npm --prefix firebase/test test"

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  where,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from "firebase/firestore";

let env;

const student = { uid: "student1", email: "student1@example.com" };
const other = { uid: "student2", email: "student2@example.com" };
const driver = { uid: "driver1", email: "driver1@example.com" };
const admin = { uid: "admin1", email: "admin1@example.com" };
const inactive = { uid: "gone1", email: "gone1@example.com" };
const noProfile = { uid: "new1", email: "new1@example.com" };

const db = (user) =>
  env.authenticatedContext(user.uid, { email: user.email }).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

const profile = (user, role, isActive = true) => ({
  name: `Name of ${user.uid}`,
  email: user.email,
  role,
  isActive,
  createdAt: Timestamp.now(),
});

const newProfile = (user, overrides = {}) => ({
  name: "A Student",
  email: user.email,
  studentId: "CSE-001",
  role: "student",
  isActive: true,
  createdAt: serverTimestamp(),
  ...overrides,
});

const validRoute = {
  name: "Campus to Town",
  color: "#D94A38",
  startLocation: "Campus",
  endLocation: "Town",
  path: [
    { latitude: 22.66, longitude: 90.36 },
    { latitude: 22.7, longitude: 90.37 },
  ],
  isActive: true,
};

const validStop = { name: "Main Gate", latitude: 22.66, longitude: 90.36 };

const validBus = {
  busNumber: "BU-01",
  name: "Kirtankhola",
  routeId: "r1",
  driverUid: driver.uid,
  isActive: true,
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-bu-bus-tracker",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const admindb = context.firestore();
    await setDoc(doc(admindb, "users", student.uid), profile(student, "student"));
    await setDoc(doc(admindb, "users", other.uid), profile(other, "student"));
    await setDoc(doc(admindb, "users", driver.uid), profile(driver, "driver"));
    await setDoc(doc(admindb, "users", admin.uid), profile(admin, "admin"));
    await setDoc(
      doc(admindb, "users", inactive.uid),
      profile(inactive, "student", false),
    );
    await setDoc(doc(admindb, "routes", "r1"), validRoute);
    await setDoc(doc(admindb, "stops", "s1"), validStop);
    await setDoc(doc(admindb, "buses", "b1"), validBus);
    await setDoc(doc(admindb, "routeStops", "r1_s1"), {
      routeId: "r1",
      stopId: "s1",
      sequence: 0,
    });
    await setDoc(doc(admindb, "announcements", "a1"), {
      title: "Holiday",
      message: "No buses on Friday.",
      createdAt: Timestamp.now(),
      isActive: true,
    });
    await setDoc(doc(admindb, "trips", "t1"), {
      busId: "b1",
      driverUid: driver.uid,
      routeId: "r1",
      status: "active",
      startedAt: Timestamp.now(),
      endedAt: null,
    });
  });
});

describe("without signing in", () => {
  test("routes, stops, buses and announcements can be read", async () => {
    for (const path of [
      "routes/r1",
      "stops/s1",
      "buses/b1",
      "routeStops/r1_s1",
      "announcements/a1",
    ]) {
      await assertSucceeds(getDoc(doc(anonymous(), path)));
    }
  });

  test("profiles and trips cannot be read", async () => {
    for (const path of ["users/student1", "users/admin1", "trips/t1"]) {
      await assertFails(getDoc(doc(anonymous(), path)));
    }
  });

  test("nothing can be written", async () => {
    await assertFails(setDoc(doc(anonymous(), "routes/x"), validRoute));
    await assertFails(setDoc(doc(anonymous(), "stops/x"), validStop));
    await assertFails(setDoc(doc(anonymous(), "buses/x"), validBus));
    await assertFails(
      setDoc(doc(anonymous(), "announcements/x"), {
        title: "Fake",
        message: "No buses today.",
        createdAt: Timestamp.now(),
        isActive: true,
      }),
    );
    await assertFails(setDoc(doc(anonymous(), "users/x"), newProfile(student)));
    await assertFails(updateDoc(doc(anonymous(), "routes/r1"), { name: "Hacked" }));
    await assertFails(updateDoc(doc(anonymous(), "buses/b1"), { driverUid: "me" }));
    await assertFails(deleteDoc(doc(anonymous(), "routes/r1")));
    await assertFails(deleteDoc(doc(anonymous(), "announcements/a1")));
  });
});

describe("creating a profile", () => {
  test("a person can create their own, as an active student", async () => {
    await assertSucceeds(
      setDoc(doc(db(noProfile), "users", noProfile.uid), newProfile(noProfile)),
    );
  });

  test("the student id is optional", async () => {
    const { studentId, ...withoutId } = newProfile(noProfile);
    await assertSucceeds(
      setDoc(doc(db(noProfile), "users", noProfile.uid), withoutId),
    );
  });

  test("not as a driver or an admin", async () => {
    for (const role of ["driver", "admin", "superuser"]) {
      await assertFails(
        setDoc(
          doc(db(noProfile), "users", noProfile.uid),
          newProfile(noProfile, { role }),
        ),
      );
    }
  });

  test("not already deactivated", async () => {
    await assertFails(
      setDoc(
        doc(db(noProfile), "users", noProfile.uid),
        newProfile(noProfile, { isActive: false }),
      ),
    );
  });

  test("not for someone else", async () => {
    await assertFails(
      setDoc(doc(db(noProfile), "users", "someone-else"), newProfile(noProfile)),
    );
  });

  test("not with another person's email", async () => {
    await assertFails(
      setDoc(
        doc(db(noProfile), "users", noProfile.uid),
        newProfile(noProfile, { email: admin.email }),
      ),
    );
  });

  test("not with extra fields", async () => {
    await assertFails(
      setDoc(
        doc(db(noProfile), "users", noProfile.uid),
        newProfile(noProfile, { isAdmin: true }),
      ),
    );
  });

  test("not with a made-up creation time", async () => {
    await assertFails(
      setDoc(
        doc(db(noProfile), "users", noProfile.uid),
        newProfile(noProfile, { createdAt: Timestamp.fromMillis(0) }),
      ),
    );
  });

  test("not with an empty or oversized name", async () => {
    for (const name of ["", "x".repeat(81)]) {
      await assertFails(
        setDoc(
          doc(db(noProfile), "users", noProfile.uid),
          newProfile(noProfile, { name }),
        ),
      );
    }
  });
});

describe("reading profiles", () => {
  test("a person can read their own", async () => {
    await assertSucceeds(getDoc(doc(db(student), "users", student.uid)));
  });

  test("but not another person's", async () => {
    await assertFails(getDoc(doc(db(student), "users", other.uid)));
    await assertFails(getDoc(doc(db(driver), "users", student.uid)));
  });

  test("an admin can read anyone's", async () => {
    await assertSucceeds(getDoc(doc(db(admin), "users", student.uid)));
  });
});

describe("listing the drivers", () => {
  const drivers = (user) =>
    getDocs(query(collection(db(user), "users"), where("role", "==", "driver")));

  test("an admin can", async () => {
    await assertSucceeds(drivers(admin));
  });

  test("an admin can list everyone, and nobody else can", async () => {
    await assertSucceeds(getDocs(collection(db(admin), "users")));
    for (const user of [student, driver, inactive, noProfile]) {
      await assertFails(getDocs(collection(db(user), "users")));
    }
    await assertFails(getDocs(collection(anonymous(), "users")));
  });

  test("an admin can change a role and the active flag together", async () => {
    await assertSucceeds(
      updateDoc(doc(db(admin), "users", student.uid), {
        role: "driver",
        isActive: true,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(admin), "users", driver.uid), {
        role: "student",
        isActive: false,
      }),
    );
  });

  test("nobody else can", async () => {
    for (const user of [student, driver, inactive, noProfile]) {
      await assertFails(drivers(user));
    }
    await assertFails(
      getDocs(query(collection(anonymous(), "users"), where("role", "==", "driver"))),
    );
  });
});

describe("changing a profile", () => {
  test("a person can correct their name and student id", async () => {
    await assertSucceeds(
      updateDoc(doc(db(student), "users", student.uid), {
        name: "New Name",
        studentId: "CSE-042",
      }),
    );
  });

  test("a person cannot make themselves a driver or an admin", async () => {
    for (const role of ["driver", "admin"]) {
      await assertFails(
        updateDoc(doc(db(student), "users", student.uid), { role }),
      );
    }
  });

  test("a driver cannot make themselves an admin", async () => {
    await assertFails(
      updateDoc(doc(db(driver), "users", driver.uid), { role: "admin" }),
    );
  });

  test("a person cannot change their email or reactivate themselves", async () => {
    await assertFails(
      updateDoc(doc(db(student), "users", student.uid), {
        email: "x@example.com",
      }),
    );
    await assertFails(
      updateDoc(doc(db(inactive), "users", inactive.uid), { isActive: true }),
    );
  });

  test("a deactivated person cannot edit their profile", async () => {
    await assertFails(
      updateDoc(doc(db(inactive), "users", inactive.uid), { name: "Still me" }),
    );
  });

  test("a person cannot change another person's profile", async () => {
    await assertFails(
      updateDoc(doc(db(student), "users", other.uid), { name: "Hacked" }),
    );
  });

  test("an admin can change a role and deactivate an account", async () => {
    await assertSucceeds(
      updateDoc(doc(db(admin), "users", student.uid), { role: "driver" }),
    );
    await assertSucceeds(
      updateDoc(doc(db(admin), "users", student.uid), { isActive: false }),
    );
  });

  test("an admin cannot set a role that does not exist", async () => {
    await assertFails(
      updateDoc(doc(db(admin), "users", student.uid), { role: "owner" }),
    );
  });

  test("an admin cannot rewrite the email or creation time", async () => {
    await assertFails(
      updateDoc(doc(db(admin), "users", student.uid), { email: "x@example.com" }),
    );
  });

  test("nobody can delete a profile", async () => {
    await assertFails(deleteDoc(doc(db(student), "users", student.uid)));
    await assertFails(deleteDoc(doc(db(admin), "users", student.uid)));
  });
});

describe("routes, stops, buses and announcements", () => {
  const paths = ["routes/r1", "stops/s1", "buses/b1", "routeStops/r1_s1", "announcements/a1"];

  test("any signed-in person can read them, as the public can", async () => {
    for (const path of paths) {
      await assertSucceeds(getDoc(doc(db(student), path)));
      await assertSucceeds(getDoc(doc(db(driver), path)));
      await assertSucceeds(getDoc(doc(db(inactive), path)));
      await assertSucceeds(getDoc(doc(db(noProfile), path)));
    }
  });

  test("a deactivated account or one with no profile cannot write them", async () => {
    for (const user of [inactive, noProfile]) {
      await assertFails(setDoc(doc(db(user), "routes/r2"), validRoute));
      await assertFails(updateDoc(doc(db(user), "buses/b1"), { driverUid: user.uid }));
      await assertFails(deleteDoc(doc(db(user), "stops/s1")));
    }
  });

  test("a deactivated admin cannot write them", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), "users", admin.uid), {
        isActive: false,
      });
    });
    await assertFails(setDoc(doc(db(admin), "routes/r2"), validRoute));
    await assertFails(deleteDoc(doc(db(admin), "stops/s1")));
  });

  test("students and drivers cannot write them", async () => {
    for (const user of [student, driver]) {
      await assertFails(setDoc(doc(db(user), "routes/r2"), validRoute));
      await assertFails(setDoc(doc(db(user), "stops/s2"), validStop));
      await assertFails(setDoc(doc(db(user), "buses/b2"), validBus));
      await assertFails(updateDoc(doc(db(user), "buses/b1"), { driverUid: user.uid }));
      await assertFails(deleteDoc(doc(db(user), "routes/r1")));
    }
  });

  test("an admin can write valid ones", async () => {
    await assertSucceeds(setDoc(doc(db(admin), "routes/r2"), validRoute));
    await assertSucceeds(setDoc(doc(db(admin), "stops/s2"), validStop));
    await assertSucceeds(setDoc(doc(db(admin), "buses/b2"), validBus));
    await assertSucceeds(
      setDoc(doc(db(admin), "routeStops/r2_s2"), {
        routeId: "r2",
        stopId: "s2",
        sequence: 1,
      }),
    );
    await assertSucceeds(
      setDoc(doc(db(admin), "announcements/a2"), {
        title: "Notice",
        message: "Route change on Sunday.",
        createdAt: Timestamp.now(),
        isActive: true,
      }),
    );
    await assertSucceeds(deleteDoc(doc(db(admin), "stops/s1")));
  });

  test("a route may list its stops in order", async () => {
    await assertSucceeds(
      setDoc(doc(db(admin), "routes/r3"), { ...validRoute, stopIds: ["s1", "s2"] }),
    );
    await assertFails(
      setDoc(doc(db(admin), "routes/bad"), { ...validRoute, stopIds: "s1" }),
    );
  });

  test("an admin cannot write invalid ones", async () => {
    await assertFails(
      setDoc(doc(db(admin), "routes/bad"), { ...validRoute, color: "red" }),
    );
    await assertFails(
      setDoc(doc(db(admin), "routes/bad"), {
        ...validRoute,
        path: [{ latitude: 22.66, longitude: 90.36 }],
      }),
    );
    await assertFails(
      setDoc(doc(db(admin), "stops/bad"), { ...validStop, latitude: 122 }),
    );
    await assertFails(
      setDoc(doc(db(admin), "stops/bad"), { ...validStop, longitude: "90.36" }),
    );
    await assertFails(
      setDoc(doc(db(admin), "buses/bad"), { ...validBus, busNumber: "" }),
    );
    await assertFails(
      setDoc(doc(db(admin), "buses/bad"), { ...validBus, owner: "me" }),
    );
    await assertFails(
      setDoc(doc(db(admin), "routeStops/bad"), {
        routeId: "r1",
        stopId: "s1",
        sequence: -1,
      }),
    );
  });
});

describe("the schedule", () => {
  const timetable = (overrides = {}) => ({
    group: "student",
    route: "01",
    stops: [{ bn: "বিশ্ববিদ্যালয়", en: "University" }],
    departures: [
      {
        from: { bn: "বিশ্ববিদ্যালয়", en: "University" },
        trips: [{ time: "08:30", vehicles: { bn: "চিত্রা", en: "Chitra" } }],
      },
    ],
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "timetables/student-01"), {
        ...timetable(),
        updatedAt: Timestamp.now(),
      });
    });
  });

  test("anyone can read it, signed in or not", async () => {
    await assertSucceeds(getDoc(doc(anonymous(), "timetables/student-01")));
    await assertSucceeds(getDoc(doc(db(student), "timetables/student-01")));
    await assertSucceeds(getDoc(doc(db(inactive), "timetables/student-01")));
  });

  test("an admin can add, change and delete a timetable", async () => {
    await assertSucceeds(
      setDoc(doc(db(admin), "timetables/teacher-04"), timetable({ group: "teacher", route: "04" })),
    );
    await assertSucceeds(
      setDoc(doc(db(admin), "timetables/student-01"), timetable({ stops: [] })),
    );
    await assertSucceeds(deleteDoc(doc(db(admin), "timetables/student-01")));
  });

  test("nobody else can change it", async () => {
    for (const user of [student, driver, inactive, noProfile]) {
      await assertFails(setDoc(doc(db(user), "timetables/x"), timetable()));
      await assertFails(
        setDoc(doc(db(user), "timetables/student-01"), timetable({ route: "99" })),
      );
      await assertFails(deleteDoc(doc(db(user), "timetables/student-01")));
    }
    await assertFails(setDoc(doc(anonymous(), "timetables/x"), timetable()));
    await assertFails(deleteDoc(doc(anonymous(), "timetables/student-01")));
  });

  test("an admin cannot save a malformed timetable", async () => {
    for (const bad of [
      { group: "visitors" },
      { route: "" },
      { route: "a-very-long-route-number" },
      { stops: "none" },
      { departures: [] },
      { departures: "soon" },
      { updatedAt: Timestamp.fromMillis(0) },
      { note: "extra field" },
    ]) {
      await assertFails(
        setDoc(doc(db(admin), "timetables/bad"), timetable(bad)),
      );
    }
    const { stops, ...missing } = timetable();
    await assertFails(setDoc(doc(db(admin), "timetables/bad"), missing));
  });
});

describe("trips", () => {
  test("no client can create, change or delete a trip", async () => {
    const trip = {
      busId: "b1",
      driverUid: driver.uid,
      routeId: "r1",
      status: "active",
      startedAt: Timestamp.now(),
      endedAt: null,
    };
    for (const user of [student, driver, admin]) {
      await assertFails(setDoc(doc(db(user), "trips/new"), trip));
      await assertFails(updateDoc(doc(db(user), "trips/t1"), { status: "ended" }));
      await assertFails(deleteDoc(doc(db(user), "trips/t1")));
    }
  });

  test("a driver can read their own trip", async () => {
    await assertSucceeds(getDoc(doc(db(driver), "trips/t1")));
  });

  test("an admin can read any trip", async () => {
    await assertSucceeds(getDoc(doc(db(admin), "trips/t1")));
  });

  test("other people cannot read it", async () => {
    await assertFails(getDoc(doc(db(student), "trips/t1")));
  });
});

describe("anything not listed in the rules", () => {
  test("is closed, even to an admin", async () => {
    await assertFails(getDoc(doc(db(admin), "secrets/x")));
    await assertFails(setDoc(doc(db(admin), "secrets/x"), { a: 1 }));
  });
});
