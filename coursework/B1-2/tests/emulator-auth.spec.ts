import { randomUUID } from "node:crypto"
import { expect, test } from "@playwright/test"
import { deleteApp, initializeApp } from "firebase/app"
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth"
import {
  collection,
  connectFirestoreEmulator,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  setDoc,
} from "firebase/firestore"

const firebaseConfig = {
  apiKey: "synthetic-emulator-key",
  appId: "synthetic-emulator-app",
  authDomain: "benchbook-local.firebaseapp.com",
  projectId: "benchbook-local",
} as const

const createEmulatorClient = () => {
  const app = initializeApp(firebaseConfig, `emulator-contract-${randomUUID()}`)
  const auth = getAuth(app)
  const firestore = getFirestore(app)
  connectAuthEmulator(auth, "http://firebase:9099", { disableWarnings: true })
  connectFirestoreEmulator(firestore, "firebase", 8080)
  return { app, auth, firestore } as const
}

test("denies workshop reads when the SDK client is signed out", async () => {
  // Given: an official SDK client connected to both local emulators without a user.
  const client = createEmulatorClient()

  try {
    // When: the signed-out client reads the protected collection.
    const operation = getDocs(collection(client.firestore, "workshops"))

    // Then: the checked-in Firestore rules reject the ordinary read.
    await expect(operation).rejects.toMatchObject({ code: "permission-denied" })
  } finally {
    await deleteApp(client.app)
  }
})

test("denies workshop writes when the SDK client is signed out", async () => {
  // Given: an official SDK client connected to both local emulators without a user.
  const client = createEmulatorClient()

  try {
    // When: the signed-out client writes a synthetic workshop.
    const operation = setDoc(doc(client.firestore, "workshops", "signed-out-write"), {
      title: "Synthetic signed-out fixture",
    })

    // Then: the checked-in Firestore rules reject the ordinary write.
    await expect(operation).rejects.toMatchObject({ code: "permission-denied" })
  } finally {
    await deleteApp(client.app)
  }
})

test("allows workshop data access after anonymous emulator sign-in", async () => {
  // Given: a synthetic anonymous user created by the local Auth emulator.
  const client = createEmulatorClient()

  try {
    await signInAnonymously(client.auth)
    const workshop = doc(client.firestore, "workshops", "signed-in-access")

    // When: the signed-in SDK client writes and reads a synthetic workshop.
    await setDoc(workshop, { title: "Synthetic signed-in fixture" })
    const snapshot = await getDoc(workshop)

    // Then: the rules allow the authenticated request and preserve its data.
    expect(snapshot.data()).toEqual({ title: "Synthetic signed-in fixture" })
  } finally {
    await deleteApp(client.app)
  }
})
