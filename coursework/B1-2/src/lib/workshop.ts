import { z } from "zod"

export const workshopStatusValues = ["open", "full", "cancelled"] as const
export const workshopStatusSchema = z.enum(workshopStatusValues)
export type WorkshopStatus = z.infer<typeof workshopStatusSchema>

export const workshopInputSchema = z.object({
  title: z.string().trim().min(3, "Use at least 3 characters.").max(80),
  summary: z.string().trim().min(12, "Add at least 12 characters.").max(240),
  facilitator: z.string().trim().min(2, "Add a facilitator.").max(60),
  location: z.string().trim().min(2, "Add a location.").max(80),
  startsAt: z.string().datetime({ local: true }),
  capacity: z.coerce.number().int().min(1).max(80),
  status: workshopStatusSchema,
})

export type WorkshopInput = z.infer<typeof workshopInputSchema>
export type WorkshopId = z.infer<typeof workshopIdSchema>

const workshopIdSchema = z.string().min(1).brand("WorkshopId")
export const workshopSchema = workshopInputSchema.extend({ id: workshopIdSchema })
export type Workshop = z.infer<typeof workshopSchema>

export type FieldErrors = Readonly<Partial<Record<keyof WorkshopInput, string>>>

export const parseWorkshopInput = (
  value: Readonly<Record<keyof WorkshopInput, string>>,
):
  | { readonly success: true; readonly data: WorkshopInput }
  | { readonly success: false; readonly errors: FieldErrors } => {
  const result = workshopInputSchema.safeParse(value)
  if (result.success) return { success: true, data: result.data }
  const errors: Partial<Record<keyof WorkshopInput, string>> = {}
  for (const issue of result.error.issues) {
    const key = issue.path[0]
    if (typeof key === "string" && !(key in errors)) {
      const parsedKey = z
        .enum(["title", "summary", "facilitator", "location", "startsAt", "capacity", "status"])
        .safeParse(key)
      if (parsedKey.success) errors[parsedKey.data] = issue.message
    }
  }
  return { success: false, errors }
}

export const formatDate = (value: string): string =>
  new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
