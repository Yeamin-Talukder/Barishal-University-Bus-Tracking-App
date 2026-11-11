import { initializeApp } from "firebase-admin/app";

initializeApp();

export { endTrip, startTrip } from "./trips/trips";
