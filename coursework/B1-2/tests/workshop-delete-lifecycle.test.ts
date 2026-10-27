import { act, cleanup, fireEvent, render, screen } from "@testing-library/react"
import { createElement } from "react"
import { Link, MemoryRouter, Route, Routes } from "react-router-dom"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { Deferred, workshop } from "./mutation-test-helpers"

const harness = vi.hoisted(() => ({ removeWorkshop: vi.fn(), useWorkshop: vi.fn() }))

vi.mock("../src/hooks/useWorkshop", () => ({ useWorkshop: harness.useWorkshop }))
vi.mock("../src/lib/workshop-store", () => ({ removeWorkshop: harness.removeWorkshop }))

import { WorkshopDetailPage } from "../src/pages/WorkshopDetailPage"

const renderDetail = () =>
  render(
    createElement(
      MemoryRouter,
      { initialEntries: ["/workshops/current-workshop"] },
      createElement(Link, { to: "/away" }, "Leave screen"),
      createElement(
        Routes,
        null,
        createElement(Route, {
          path: "/workshops/:id",
          element: createElement(WorkshopDetailPage),
        }),
        createElement(Route, {
          path: "/workshops",
          element: createElement("h1", null, "Workshop schedule"),
        }),
        createElement(Route, { path: "/away", element: createElement("h1", null, "Away") }),
      ),
    ),
  )

beforeEach(() => {
  harness.removeWorkshop.mockReset()
  harness.useWorkshop.mockReset()
  harness.useWorkshop.mockReturnValue({
    state: { kind: "ready", item: workshop() },
    reload: vi.fn(),
  })
})

afterEach(cleanup)

describe("WorkshopDetailPage delete lifecycle ownership", () => {
  it("disables contradictory local operations while deletion is pending", () => {
    // Given: a workshop detail with a pending delete request.
    const deletion = new Deferred<void>()
    harness.removeWorkshop.mockReturnValue(deletion.promise)
    renderDetail()

    // When: the user confirms deletion.
    fireEvent.click(screen.getByRole("button", { name: "Delete" }))
    fireEvent.click(screen.getByRole("button", { name: "Delete permanently" }))

    // Then: delete, keep, and edit controls cannot imply cancellable or conflicting work.
    expect(screen.getByRole("button", { name: "Deleting…" })).toHaveProperty("disabled", true)
    expect(screen.getByRole("button", { name: "Keep workshop" })).toHaveProperty("disabled", true)
    expect(screen.getByRole("button", { name: "Edit" })).toHaveProperty("disabled", true)
    expect(screen.queryByRole("link", { name: "Edit" })).toBeNull()
  })

  it("does not navigate when deletion completes after the detail screen is left", async () => {
    // Given: the current item owns a pending delete request.
    const deletion = new Deferred<void>()
    harness.removeWorkshop.mockReturnValue(deletion.promise)
    renderDetail()
    fireEvent.click(screen.getByRole("button", { name: "Delete" }))
    fireEvent.click(screen.getByRole("button", { name: "Delete permanently" }))

    // When: global navigation leaves before deletion completes.
    fireEvent.click(screen.getByRole("link", { name: "Leave screen" }))
    await act(async () => deletion.resolve(undefined))

    // Then: the obsolete completion cannot replace the user's current route.
    expect(screen.getByRole("heading", { name: "Away" })).toBeTruthy()
    expect(screen.queryByRole("heading", { name: "Workshop schedule" })).toBeNull()
  })
})
