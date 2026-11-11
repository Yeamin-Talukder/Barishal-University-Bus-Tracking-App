import { getFirestore } from "firebase-admin/firestore";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

/**
 * Confirms the caller is signed in and is an active driver, from the user
 * document on the server. Nothing the app sends is trusted for this.
 *
 * @returns the driver's uid.
 */
export async function requireActiveDriver(request: CallableRequest): Promise<string> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to do this.");
  }

  const user = await getFirestore().doc(`users/${uid}`).get();
  if (!user.exists || user.get("isActive") !== true) {
    throw new HttpsError("permission-denied", "This account is not active.");
  }
  if (user.get("role") !== "driver") {
    throw new HttpsError("permission-denied", "Only drivers can run trips.");
  }
  return uid;
}
