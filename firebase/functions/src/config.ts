/** Settings shared by every function. */

/** Singapore: the same region as Firestore and the Realtime Database. */
export const REGION = "asia-southeast1";

/**
 * Whether callable functions reject requests without a valid App Check
 * token. Turn on once App Check is registered for the Android and iOS apps
 * and has been seen working (see FIREBASE_SETUP.md); turning it on earlier
 * would lock every phone out.
 */
export const ENFORCE_APP_CHECK = false;
