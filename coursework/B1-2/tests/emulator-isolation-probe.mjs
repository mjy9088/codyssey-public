import assert from "node:assert/strict"
import { randomUUID } from "node:crypto"
import { readFile } from "node:fs/promises"
import { deleteApp, FirebaseError, initializeApp } from "firebase/app"
import { connectAuthEmulator, deleteUser, getAuth, signInAnonymously, signOut } from "firebase/auth"
import {
  connectFirestoreEmulator,
  deleteDoc,
  doc,
  getDocFromServer,
  getFirestore,
  setDoc,
  updateDoc,
} from "firebase/firestore"

const projectId = process.env.FIREBASE_TEST_PROJECT_ID
if (
  !projectId?.startsWith("demo-") ||
  process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8085" ||
  process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9099"
) {
  throw new Error("This acceptance probe requires the isolated native demo-project emulators")
}
const client = () => {
  const app = initializeApp({ projectId, apiKey: "synthetic-probe-key" }, `probe-${randomUUID()}`)
  const auth = getAuth(app)
  const db = getFirestore(app)
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true })
  connectFirestoreEmulator(db, "127.0.0.1", 8085)
  return { app, auth, db }
}
const a = client()
const b = client()
const signedOut = client()
const id = `verification-${randomUUID()}`
const ownerDoc = doc(a.db, "workshops", id)
const otherDoc = doc(b.db, "workshops", id)
const createdUsers = []
let recordCreated = false
const cleanupFailures = []
const permitted = async (operation) => {
  try {
    await operation()
    return true
  } catch (error) {
    if (error instanceof FirebaseError && error.code === "permission-denied") return false
    throw error
  }
}
const input = {
  title: "Namespaced acceptance workshop",
  summary: "Disposable synthetic verification record, never real user data.",
  facilitator: "Synthetic Operator",
  location: "Emulator bench",
  startsAt: "2026-12-12T14:00",
  capacity: 8,
  status: "open",
}
try {
  const installed = await fetch(
    `http://127.0.0.1:8085/emulator/v1/projects/${projectId}:securityRules`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        rules: {
          files: [
            {
              name: "firestore.rules",
              content: await readFile(new URL("../firestore.rules", import.meta.url), "utf8"),
            },
          ],
        },
      }),
      signal: AbortSignal.timeout(10000),
    },
  )
  assert.equal(installed.ok, true)
  assert.equal(await permitted(() => getDocFromServer(ownerDoc)), false)
  assert.equal(await permitted(() => setDoc(ownerDoc, input)), false)
  const owner = (await signInAnonymously(a.auth)).user
  const other = (await signInAnonymously(b.auth)).user
  createdUsers.push(owner, other)
  assert.notEqual(owner.uid, other.uid)
  assert.equal((await signInAnonymously(b.auth)).user.uid, other.uid)
  await setDoc(ownerDoc, input)
  recordCreated = true
  await setDoc(ownerDoc, input)
  assert.deepEqual((await getDocFromServer(ownerDoc)).data(), input)
  await updateDoc(ownerDoc, { title: "Persisted owner update" })
  assert.equal((await getDocFromServer(ownerDoc)).data()?.title, "Persisted owner update")
  await deleteDoc(ownerDoc)
  assert.equal((await getDocFromServer(ownerDoc)).exists(), false)
  await setDoc(ownerDoc, input)
  createdUsers.push((await signInAnonymously(signedOut.auth)).user)
  await signOut(signedOut.auth)
  assert.equal(signedOut.auth.currentUser, null)
  const signedOutDoc = doc(signedOut.db, "workshops", id)
  assert.equal(await permitted(() => getDocFromServer(signedOutDoc)), false)
  const crossUserRead = await permitted(() => getDocFromServer(otherDoc))
  const crossUserUpdate = await permitted(() => updateDoc(otherDoc, { title: "Cross-user probe" }))
  const crossUserDelete = await permitted(() => deleteDoc(otherDoc))
  console.log(
    JSON.stringify(
      {
        backend: "real-auth-and-firestore-emulators",
        checkedInRules: true,
        unauthenticatedReadDenied: true,
        unauthenticatedWriteDenied: true,
        creatorCRUDAndPersistence: true,
        signOutDenial: true,
        repeatSignInSameUser: true,
        crossUserRead,
        crossUserUpdate,
        crossUserDelete,
        ownerIsolation: crossUserRead || crossUserUpdate || crossUserDelete ? "FAIL" : "PASS",
      },
      null,
      2,
    ),
  )
  process.exitCode = crossUserRead || crossUserUpdate || crossUserDelete ? 2 : 0
} finally {
  const results = recordCreated ? await Promise.allSettled([deleteDoc(ownerDoc)]) : []
  results.push(...(await Promise.allSettled(createdUsers.map((user) => deleteUser(user)))))
  results.push(
    ...(await Promise.allSettled([deleteApp(a.app), deleteApp(b.app), deleteApp(signedOut.app)])),
  )
  cleanupFailures.push(...results.filter((result) => result.status === "rejected"))
}
if (cleanupFailures.length) {
  throw new AggregateError(
    cleanupFailures.map((result) => result.reason),
    "Probe cleanup failed",
  )
}
