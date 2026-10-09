import { getApp, getApps, initializeApp } from "firebase/app"
import { connectAuthEmulator, getAuth } from "firebase/auth"
import { connectFirestoreEmulator, getFirestore } from "firebase/firestore"

const app =
  getApps().length > 0
    ? getApp()
    : initializeApp({
        apiKey: import.meta.env.VITE_FIREBASE_API_KEY ?? "local-emulator-key",
        authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ?? "benchbook-local.firebaseapp.com",
        projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID ?? "benchbook-local",
      })

export const auth = getAuth(app)
export const database = getFirestore(app)

const useEmulators = (import.meta.env.VITE_USE_EMULATORS ?? "true") === "true"
const isHostBrowser = ["localhost", "127.0.0.1"].includes(window.location.hostname)

if (useEmulators) {
  const host = isHostBrowser ? window.location.hostname : "firebase"
  connectAuthEmulator(auth, `http://${host}:9099`, { disableWarnings: true })
  connectFirestoreEmulator(database, host, isHostBrowser ? 8085 : 8080)
}
