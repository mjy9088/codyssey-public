import { collection, doc, writeBatch } from "firebase/firestore"
import { database } from "./firebase"
import type { WorkshopInput } from "./workshop"

const sampleWorkshops = [
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

export const seedWorkshops = async (): Promise<void> => {
  const batch = writeBatch(database)
  const workshops = collection(database, "workshops")
  for (const sample of sampleWorkshops) batch.set(doc(workshops), sample)
  await batch.commit()
}
