import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  updateDoc,
} from "firebase/firestore"
import { database } from "./firebase"
import { type Workshop, type WorkshopId, type WorkshopInput, workshopSchema } from "./workshop"

const workshops = collection(database, "workshops")

export const listWorkshops = async (): Promise<readonly Workshop[]> => {
  const snapshot = await getDocs(query(workshops, orderBy("startsAt", "asc")))
  return snapshot.docs.map((entry) => workshopSchema.parse({ id: entry.id, ...entry.data() }))
}

export const getWorkshop = async (id: string): Promise<Workshop | null> => {
  const snapshot = await getDoc(doc(workshops, id))
  return snapshot.exists() ? workshopSchema.parse({ id: snapshot.id, ...snapshot.data() }) : null
}

export const createWorkshop = async (input: WorkshopInput): Promise<WorkshopId> => {
  const created = await addDoc(workshops, input)
  return workshopSchema.shape.id.parse(created.id)
}

export const updateWorkshop = async (id: WorkshopId, input: WorkshopInput): Promise<void> => {
  await updateDoc(doc(workshops, id), input)
}

export const removeWorkshop = async (id: WorkshopId): Promise<void> => {
  await deleteDoc(doc(workshops, id))
}

export const seedWorkshops = async (): Promise<void> => {
  const samples = [
    {
      title: "Repair a desk lamp",
      summary: "Diagnose a faulty switch and leave with a safely rewired lamp.",
      facilitator: "Mara Chen",
      location: "Electrical bench",
      startsAt: "2026-10-16T18:00",
      capacity: 8,
      status: "open",
    },
    {
      title: "Print a field notebook",
      summary: "Fold, stitch, and trim a pocket notebook using archival paper.",
      facilitator: "Owen Bell",
      location: "Bindery table",
      startsAt: "2026-10-18T10:00",
      capacity: 12,
      status: "full",
    },
    {
      title: "Sharpen kitchen knives",
      summary: "Practice angle control on water stones with guided safety checks.",
      facilitator: "Iris Park",
      location: "Wet workshop",
      startsAt: "2026-10-22T17:30",
      capacity: 6,
      status: "open",
    },
    {
      title: "Build a plant stand",
      summary: "Cut and join a compact timber stand from a measured drawing.",
      facilitator: "Theo Ward",
      location: "Wood shop",
      startsAt: "2026-10-25T09:30",
      capacity: 10,
      status: "cancelled",
    },
    {
      title: "Patch visible denim",
      summary: "Use sashiko-inspired stitching to reinforce a worn garment.",
      facilitator: "Nina Sol",
      location: "Textile room",
      startsAt: "2026-11-01T13:00",
      capacity: 14,
      status: "open",
    },
  ] as const satisfies readonly WorkshopInput[]
  await Promise.all(samples.map((sample) => addDoc(workshops, sample)))
}
