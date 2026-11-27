import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { config } from "./config";

export function firebaseMessaging() {
  if (config.FIREBASE_ENABLED !== "true") return null;
  if (
    !config.FIREBASE_PROJECT_ID ||
    !config.FIREBASE_SERVICE_ACCOUNT_JSON_BASE64
  ) {
    throw new Error(
      "Firebase is enabled but its project credentials are not configured",
    );
  }
  const app =
    getApps()[0] ??
    initializeApp({
      credential: cert(
        JSON.parse(
          Buffer.from(
            config.FIREBASE_SERVICE_ACCOUNT_JSON_BASE64,
            "base64",
          ).toString("utf8"),
        ),
      ),
      projectId: config.FIREBASE_PROJECT_ID,
    });
  return getMessaging(app);
}
