import { fireEvent, screen } from "@testing-library/react"
import type { Workshop } from "../src/lib/workshop"
import { workshopSchema } from "../src/lib/workshop"

export class Deferred<T> {
  readonly promise: Promise<T>
  private resolvePromise: (value: T) => void = () => undefined
  private rejectPromise: (reason?: unknown) => void = () => undefined

  constructor() {
    this.promise = new Promise<T>((resolve, reject) => {
      this.resolvePromise = resolve
      this.rejectPromise = reject
    })
  }

  resolve(value: T): void {
    this.resolvePromise(value)
  }

  reject(reason: unknown): void {
    this.rejectPromise(reason)
  }
}

export const workshop = (id = "current-workshop"): Workshop =>
  workshopSchema.parse({
    id,
    title: "Lifecycle workshop",
    summary: "A practical workshop used for mutation lifecycle testing.",
    facilitator: "Morgan Lee",
    location: "Test bench",
    startsAt: "2026-10-18T10:00:00",
    capacity: 8,
    status: "open",
  })

export const fillWorkshopForm = (title: string): void => {
  fireEvent.change(screen.getByLabelText("Workshop title"), { target: { value: title } })
  fireEvent.change(screen.getByLabelText("Summary"), {
    target: { value: "A synthetic draft retained across a failed save request." },
  })
  fireEvent.change(screen.getByLabelText("Facilitator"), { target: { value: "Test Operator" } })
  fireEvent.change(screen.getByLabelText("Location"), { target: { value: "Local bench" } })
  fireEvent.change(screen.getByLabelText("Start date and time"), {
    target: { value: "2026-12-12T14:00" },
  })
  fireEvent.change(screen.getByLabelText("Capacity"), { target: { value: "8" } })
}
