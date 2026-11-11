import { getDatabase, ServerValue } from "firebase-admin/database";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireActiveDriver } from "../auth/driver";
import { ENFORCE_APP_CHECK, REGION } from "../config";

const callOptions = { region: REGION, enforceAppCheck: ENFORCE_APP_CHECK };

interface ActiveTrip {
  tripId: string;
  driverUid: string;
  status: string;
  routeId: string;
}

/**
 * Starts a trip for the bus assigned to the calling driver.
 *
 * The driver does not choose the bus or the route: both are read from the
 * bus document an admin maintains. On success the bus has an entry under
 * `activeTrips/{busId}` in the Realtime Database, which is what the security
 * rules check before accepting that driver's GPS positions for that bus.
 *
 * Calling it again while the trip is running returns the same trip.
 */
export const startTrip = onCall(callOptions, async (request) => {
  const uid = await requireActiveDriver(request);
  const firestore = getFirestore();

  const buses = await firestore
    .collection("buses")
    .where("driverUid", "==", uid)
    .where("isActive", "==", true)
    .limit(2)
    .get();
  if (buses.empty) {
    throw new HttpsError("failed-precondition", "No active bus is assigned to you.");
  }
  if (buses.size > 1) {
    throw new HttpsError(
      "failed-precondition",
      "More than one bus is assigned to you. Ask the transport office to fix this.",
    );
  }
  const bus = buses.docs[0];

  const routeId = bus.get("routeId");
  if (typeof routeId !== "string" || routeId.length === 0) {
    throw new HttpsError("failed-precondition", "Your bus has no route assigned.");
  }
  const route = await firestore.doc(`routes/${routeId}`).get();
  if (!route.exists || route.get("isActive") !== true) {
    throw new HttpsError("failed-precondition", "Your bus's route is not running.");
  }

  // Claim the bus atomically, so two phones cannot both start a trip on it.
  const trip = firestore.collection("trips").doc();
  const activeRef = getDatabase().ref(`activeTrips/${bus.id}`);
  const claim = await activeRef.transaction((current: ActiveTrip | null) => {
    if (current && current.status === "active") {
      return; // Abort: the bus already has a trip.
    }
    return {
      tripId: trip.id,
      driverUid: uid,
      status: "active",
      routeId,
      startedAt: ServerValue.TIMESTAMP,
    };
  });

  if (!claim.committed) {
    const existing = claim.snapshot.val() as ActiveTrip | null;
    if (existing && existing.driverUid === uid) {
      return { tripId: existing.tripId, busId: bus.id, routeId: existing.routeId };
    }
    throw new HttpsError("already-exists", "This bus already has a trip in progress.");
  }

  try {
    await trip.set({
      busId: bus.id,
      driverUid: uid,
      routeId,
      status: "active",
      startedAt: FieldValue.serverTimestamp(),
      endedAt: null,
    });
  } catch (error) {
    // Do not leave the bus claimed by a trip that was never recorded.
    await activeRef.remove();
    throw error;
  }

  return { tripId: trip.id, busId: bus.id, routeId };
});

/**
 * Ends the calling driver's trip: records the end time, releases the bus and
 * removes its live position, so passengers no longer see it as running.
 */
export const endTrip = onCall(callOptions, async (request) => {
  const uid = await requireActiveDriver(request);
  const database = getDatabase();

  const active = await database
    .ref("activeTrips")
    .orderByChild("driverUid")
    .equalTo(uid)
    .get();
  if (!active.exists()) {
    throw new HttpsError("failed-precondition", "You have no trip in progress.");
  }

  const ended: string[] = [];
  const writes: Promise<unknown>[] = [];
  active.forEach((entry) => {
    const busId = entry.key as string;
    const trip = entry.val() as ActiveTrip;
    ended.push(trip.tripId);
    writes.push(
      getFirestore().doc(`trips/${trip.tripId}`).set(
        { status: "ended", endedAt: FieldValue.serverTimestamp() },
        { merge: true },
      ),
      database.ref().update({
        [`activeTrips/${busId}`]: null,
        [`liveLocations/${busId}`]: null,
      }),
    );
  });
  await Promise.all(writes);

  return { tripIds: ended };
});
