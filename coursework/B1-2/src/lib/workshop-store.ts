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
