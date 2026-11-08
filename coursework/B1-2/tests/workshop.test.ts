import { describe, expect, it } from "vitest"
import { parseWorkshopInput } from "../src/lib/workshop"

const valid = {
  title: "Repair a radio",
  summary: "Learn to trace a simple audio fault safely.",
  facilitator: "Mara Chen",
  location: "Electronics bench",
  startsAt: "2026-10-18T10:00",
  capacity: "8",
  status: "open",
} as const

describe("parseWorkshopInput", () => {
  it("returns typed data when all controlled fields are valid", () => {
    const result = parseWorkshopInput(valid)
    expect(result.success).toBe(true)
    if (result.success) expect(result.data.capacity).toBe(8)
  })

  it("returns field errors when required content is missing", () => {
    const result = parseWorkshopInput({ ...valid, title: "", summary: "short" })
    expect(result.success).toBe(false)
    if (!result.success) expect(Object.keys(result.errors).sort()).toEqual(["summary", "title"])
  })

  it.each([
    ["capacity", "0"],
    ["capacity", "81"],
    ["capacity", "1.5"],
    ["capacity", "not-a-number"],
    ["capacity", ""],
    ["startsAt", "2026-02-30T10:00"],
    ["startsAt", "not-a-date"],
    ["status", "unknown"],
    ["facilitator", " "],
    ["location", " "],
  ] as const)("rejects invalid %s input %s at the form boundary", (field, value) => {
    const result = parseWorkshopInput({ ...valid, [field]: value })
    expect(result.success).toBe(false)
    if (!result.success) expect(result.errors[field]).toBeDefined()
  })

  it.each(["1", "80"])("accepts capacity boundary %s and trims authored text", (capacity) => {
    const result = parseWorkshopInput({ ...valid, title: "  Repair a radio  ", capacity })
    expect(result).toEqual({
      success: true,
      data: { ...valid, title: "Repair a radio", capacity: Number(capacity) },
    })
  })
})
