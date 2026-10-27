import { act, cleanup, fireEvent, render, screen } from "@testing-library/react"
import { createElement } from "react"
import { Link, MemoryRouter, Route, Routes } from "react-router-dom"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import type { WorkshopId } from "../src/lib/workshop"
import { Deferred, fillWorkshopForm, workshop } from "./mutation-test-helpers"

const harness = vi.hoisted(() => ({
  auth: vi.fn(),
  createWorkshop: vi.fn(),
  updateWorkshop: vi.fn(),
  useWorkshop: vi.fn(),
}))

vi.mock("../src/context/AuthContext", () => ({ useAuth: harness.auth }))
vi.mock("../src/hooks/useWorkshop", () => ({ useWorkshop: harness.useWorkshop }))
vi.mock("../src/lib/workshop-store", () => ({
  createWorkshop: harness.createWorkshop,
  updateWorkshop: harness.updateWorkshop,
}))

import { EditWorkshopPage } from "../src/pages/EditWorkshopPage"
import { NewWorkshopPage } from "../src/pages/NewWorkshopPage"

const retryAuth = vi.fn()

const renderRoutes = (initialEntry: string) =>
  render(
    createElement(
      MemoryRouter,
      { initialEntries: [initialEntry] },
      createElement(Link, { to: "/away" }, "Leave screen"),
      createElement(
        Routes,
        null,
        createElement(Route, { path: "/workshops/new", element: createElement(NewWorkshopPage) }),
        createElement(Route, {
          path: "/workshops/:id/edit",
          element: createElement(EditWorkshopPage),
        }),
        createElement(Route, {
          path: "/workshops/:id",
          element: createElement("h1", null, "Saved workshop"),
        }),
        createElement(Route, { path: "/away", element: createElement("h1", null, "Away") }),
      ),
    ),
  )

beforeEach(() => {
  harness.auth.mockReset()
  harness.createWorkshop.mockReset()
  harness.updateWorkshop.mockReset()
  harness.useWorkshop.mockReset()
  retryAuth.mockReset()
  harness.auth.mockReturnValue({
    state: { kind: "ready", user: { uid: "test-user" } },
    retry: retryAuth,
  })
  harness.useWorkshop.mockReturnValue({
    state: { kind: "ready", item: workshop() },
    reload: vi.fn(),
  })
})

afterEach(cleanup)

describe("NewWorkshopPage authentication gate", () => {
  it("shows authentication loading instead of offering creation", () => {
    // Given: anonymous authentication has not completed.
    harness.auth.mockReturnValue({ state: { kind: "loading" }, retry: retryAuth })

    // When: the new-workshop route renders.
    renderRoutes("/workshops/new")

    // Then: creation is unavailable until authentication is ready.
    expect(screen.getByText("Preparing workshop form…")).toBeTruthy()
    expect(screen.queryByRole("button", { name: "Create workshop" })).toBeNull()
  })

  it("offers the shared retry when authentication fails", () => {
    // Given: authentication failed at the application boundary.
    harness.auth.mockReturnValue({
      state: { kind: "error", message: "Authentication is unavailable. Try again to reconnect." },
      retry: retryAuth,
    })

    // When: the new-workshop route renders and the user retries.
    renderRoutes("/workshops/new")
    fireEvent.click(screen.getByRole("button", { name: "Try again" }))

    // Then: the page delegates recovery to the current authentication owner.
    expect(retryAuth).toHaveBeenCalledOnce()
    expect(screen.queryByRole("button", { name: "Create workshop" })).toBeNull()
  })
})

describe("Workshop save lifecycle ownership", () => {
  it("disables every local form operation while creation is pending", () => {
    // Given: a valid new-workshop draft and a pending store write.
    const write = new Deferred<WorkshopId>()
    harness.createWorkshop.mockReturnValue(write.promise)
    renderRoutes("/workshops/new")
    fillWorkshopForm("Pending workshop")

    // When: the user submits the draft.
    fireEvent.click(screen.getByRole("button", { name: "Create workshop" }))

    // Then: fields and local cancellation truthfully report that the write cannot be cancelled.
    for (const label of [
      "Workshop title",
      "Summary",
      "Facilitator",
      "Location",
      "Start date and time",
      "Capacity",
      "Status",
    ]) {
      expect(screen.getByLabelText(label)).toHaveProperty("disabled", true)
    }
    expect(screen.getByRole("button", { name: "Saving…" })).toHaveProperty("disabled", true)
    expect(screen.getByRole("button", { name: "Cancel" })).toHaveProperty("disabled", true)
    expect(screen.queryByRole("link", { name: "Cancel" })).toBeNull()
  })

  it.each([
    ["create", "/workshops/new", "Create workshop"],
    ["edit", "/workshops/current-workshop/edit", "Save changes"],
  ])(
    "does not let a late %s success navigate after the screen is left",
    async (operation, route, label) => {
      // Given: the current screen owns a pending save.
      const write = new Deferred<WorkshopId | undefined>()
      if (operation === "create") harness.createWorkshop.mockReturnValue(write.promise)
      else harness.updateWorkshop.mockReturnValue(write.promise)
      renderRoutes(route)
      if (operation === "create") fillWorkshopForm("Late workshop")
      fireEvent.click(screen.getByRole("button", { name: label }))

      // When: global navigation leaves before the backend write completes.
      fireEvent.click(screen.getByRole("link", { name: "Leave screen" }))
      await act(async () => write.resolve(workshop().id))

      // Then: completion cannot redirect the user back into the obsolete flow.
      expect(screen.getByRole("heading", { name: "Away" })).toBeTruthy()
      expect(screen.queryByRole("heading", { name: "Saved workshop" })).toBeNull()
    },
  )

  it("keeps the draft and offers a stable retry after creation fails", async () => {
    // Given: a valid draft whose first write exposes a low-level failure.
    const failedWrite = new Deferred<WorkshopId>()
    const retryWrite = new Deferred<WorkshopId>()
    harness.createWorkshop
      .mockReturnValueOnce(failedWrite.promise)
      .mockReturnValueOnce(retryWrite.promise)
    renderRoutes("/workshops/new")
    fillWorkshopForm("Retained workshop")
    fireEvent.click(screen.getByRole("button", { name: "Create workshop" }))

    // When: the first write fails and the user retries the unchanged draft.
    await act(async () => failedWrite.reject(new Error("Firebase permission-denied internals")))

    // Then: stable recovery copy is shown, the draft remains, and retry can complete normally.
    expect(screen.getByRole("alert").textContent).toBe(
      "The workshop could not be saved. Try again.",
    )
    expect(screen.queryByText("Firebase permission-denied internals")).toBeNull()
    expect(screen.getByLabelText("Workshop title")).toHaveProperty("value", "Retained workshop")
    fireEvent.click(screen.getByRole("button", { name: "Create workshop" }))
    await act(async () => retryWrite.resolve(workshop().id))
    expect(screen.getByRole("heading", { name: "Saved workshop" })).toBeTruthy()
  })
})
