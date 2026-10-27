import { act, render, renderHook } from "@testing-library/react"
import type { User } from "firebase/auth"
import { createElement } from "react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { type Workshop, workshopSchema } from "../src/lib/workshop"

class Deferred<T> {
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

const hookHarness = vi.hoisted(() => ({
  auth: vi.fn(),
  getWorkshop: vi.fn(),
  listWorkshops: vi.fn(),
}))

vi.mock("../src/context/AuthContext", () => ({ useAuth: hookHarness.auth }))
vi.mock("../src/lib/workshop-store", () => ({
  getWorkshop: hookHarness.getWorkshop,
  listWorkshops: hookHarness.listWorkshops,
}))

import { useWorkshop } from "../src/hooks/useWorkshop"
import { useWorkshops } from "../src/hooks/useWorkshops"

const user = (uid: string): User => ({
  uid,
  displayName: null,
  email: null,
  emailVerified: false,
  isAnonymous: true,
  phoneNumber: null,
  photoURL: null,
  providerData: [],
  providerId: "firebase",
  refreshToken: "",
  tenantId: null,
  metadata: {},
  delete: async () => undefined,
  getIdToken: async () => "token",
  getIdTokenResult: async () => ({
    authTime: "2026-01-01T00:00:00.000Z",
    claims: {},
    expirationTime: "2026-01-01T01:00:00.000Z",
    issuedAtTime: "2026-01-01T00:00:00.000Z",
    signInProvider: "anonymous",
    signInSecondFactor: null,
    token: "token",
  }),
  reload: async () => undefined,
  toJSON: () => ({ uid }),
})

const workshop = (id: string, title: string): Workshop =>
  workshopSchema.parse({
    id,
    title,
    summary: "A practical workshop used for lifecycle testing.",
    facilitator: "Morgan Lee",
    location: "Test bench",
    startsAt: "2026-10-18T10:00:00",
    capacity: 8,
    status: "open",
  })

const retry = vi.fn()

beforeEach(() => {
  hookHarness.auth.mockReset()
  hookHarness.getWorkshop.mockReset()
  hookHarness.listWorkshops.mockReset()
  retry.mockReset()
})

describe("useWorkshop lifecycle ownership", () => {
  it("hides the previous route immediately when route and auth ownership change", async () => {
    // Given: route A is visible while reads for routes A and B are controlled independently.
    let authValue = { state: { kind: "ready", user: user("user-a") }, retry } as const
    hookHarness.auth.mockImplementation(() => authValue)
    const routeA = new Deferred<Workshop | null>()
    const routeB = new Deferred<Workshop | null>()
    hookHarness.getWorkshop.mockImplementation((id: string) =>
      id === "route-a" ? routeA.promise : routeB.promise,
    )
    const observations: { readonly kind: string; readonly title?: string }[] = []
    const Probe = ({ workshopId }: { readonly workshopId: string }) => {
      const { state } = useWorkshop(workshopId)
      observations.push({
        kind: state.kind,
        ...(state.kind === "ready" ? { title: state.item.title } : {}),
      })
      return null
    }
    const view = render(createElement(Probe, { workshopId: "route-a" }))
    await act(async () => routeA.resolve(workshop("route-a", "Route A")))
    expect(observations.at(-1)).toEqual({ kind: "ready", title: "Route A" })

    // When: the route and authenticated user change.
    const transitionStart = observations.length
    view.rerender(createElement(Probe, { workshopId: "route-b" }))
    authValue = { state: { kind: "ready", user: user("user-b") }, retry }
    view.rerender(createElement(Probe, { workshopId: "route-b" }))

    // Then: no render for the new owner exposes route A, including the first render before effects.
    expect(observations.slice(transitionStart).every((state) => state.title !== "Route A")).toBe(
      true,
    )
    await act(async () => routeB.resolve(workshop("route-b", "Route B")))
    expect(observations.at(-1)).toEqual({ kind: "ready", title: "Route B" })
  })

  it("keeps the current workshop when an obsolete read rejects", async () => {
    // Given: user A has a pending read and user B starts a newer read for the same route.
    let authValue = { state: { kind: "ready", user: user("user-a") }, retry } as const
    hookHarness.auth.mockImplementation(() => authValue)
    const userARead = new Deferred<Workshop | null>()
    const userBRead = new Deferred<Workshop | null>()
    hookHarness.getWorkshop
      .mockImplementationOnce(() => userARead.promise)
      .mockImplementationOnce(() => userBRead.promise)
    const { result, rerender } = renderHook(() => useWorkshop("shared-route"))
    authValue = { state: { kind: "ready", user: user("user-b") }, retry }
    rerender()
    await act(async () => userBRead.resolve(workshop("shared-route", "User B workshop")))

    // When: the obsolete user A read rejects afterward.
    await act(async () => userARead.reject(new Error("obsolete read failure")))

    // Then: user B's workshop remains current.
    expect(result.current.state).toMatchObject({
      kind: "ready",
      item: { title: "User B workshop" },
    })
  })
})

describe("useWorkshops lifecycle ownership", () => {
  it("ignores stale list success across an auth transition", async () => {
    // Given: user A and user B have independently controlled list reads.
    let authValue = { state: { kind: "ready", user: user("user-a") }, retry } as const
    hookHarness.auth.mockImplementation(() => authValue)
    const userARead = new Deferred<readonly Workshop[]>()
    const userBRead = new Deferred<readonly Workshop[]>()
    hookHarness.listWorkshops
      .mockImplementationOnce(() => userARead.promise)
      .mockImplementationOnce(() => userBRead.promise)
    const { result, rerender } = renderHook(useWorkshops)

    // When: user B becomes current before user A's read succeeds.
    authValue = { state: { kind: "ready", user: user("user-b") }, retry }
    rerender()
    await act(async () => userARead.resolve([workshop("a", "User A workshop")]))

    // Then: user A's data never owns user B's visible state.
    expect(result.current.state.kind).toBe("loading")
    await act(async () => userBRead.resolve([workshop("b", "User B workshop")]))
    expect(result.current.state).toMatchObject({
      kind: "ready",
      items: [{ title: "User B workshop" }],
    })
  })

  it("settles reload without publishing after unmount", async () => {
    // Given: a caller awaits a manually started reload while the hook is mounted.
    hookHarness.auth.mockReturnValue({ state: { kind: "ready", user: user("user-a") }, retry })
    const automaticRead = new Deferred<readonly Workshop[]>()
    const manualRead = new Deferred<readonly Workshop[]>()
    hookHarness.listWorkshops
      .mockImplementationOnce(() => automaticRead.promise)
      .mockImplementationOnce(() => manualRead.promise)
    const { result, unmount } = renderHook(useWorkshops)
    let reload = Promise.resolve()
    act(() => {
      reload = result.current.reload()
    })

    // When: the owner unmounts before the awaited I/O finishes.
    unmount()
    manualRead.resolve([workshop("late", "Late workshop")])

    // Then: the public promise still settles for its awaiting caller.
    await expect(reload).resolves.toBeUndefined()
    automaticRead.resolve([])
  })
})
