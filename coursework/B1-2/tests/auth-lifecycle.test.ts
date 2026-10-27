import { act, renderHook } from "@testing-library/react"
import type { User } from "firebase/auth"
import { createElement, type PropsWithChildren, StrictMode } from "react"
import { beforeEach, describe, expect, it, vi } from "vitest"

type AuthSubscription = {
  readonly next: (user: User | null) => void
  readonly error: () => void
  readonly unsubscribe: ReturnType<typeof vi.fn>
}

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

const authHarness = vi.hoisted(
  (): {
    attempts: Promise<void>[]
    emitNullOnSubscribe: boolean
    subscriptions: AuthSubscription[]
  } => ({ attempts: [], emitNullOnSubscribe: false, subscriptions: [] }),
)

vi.mock("firebase/auth", () => ({
  onAuthStateChanged: (_auth: unknown, next: (user: User | null) => void, error: () => void) => {
    const unsubscribe = vi.fn()
    authHarness.subscriptions.push({ next, error, unsubscribe })
    if (authHarness.emitNullOnSubscribe) next(null)
    return unsubscribe
  },
  signInAnonymously: () => {
    const attempt = authHarness.attempts.shift()
    return attempt ?? Promise.resolve()
  },
}))

vi.mock("../src/lib/firebase", () => ({ auth: {} }))

import { AuthProvider, useAuth } from "../src/context/AuthContext"

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

const wrapper = ({ children }: PropsWithChildren) => createElement(AuthProvider, { children })

const strictWrapper = ({ children }: PropsWithChildren) =>
  createElement(StrictMode, null, createElement(AuthProvider, { children }))

beforeEach(() => {
  authHarness.attempts.length = 0
  authHarness.emitNullOnSubscribe = false
  authHarness.subscriptions.length = 0
})

describe("AuthProvider lifecycle ownership", () => {
  it("keeps an observed login when an older anonymous attempt rejects", async () => {
    // Given: anonymous authentication is pending for the active subscription.
    const attempt = new Deferred<void>()
    authHarness.attempts.push(attempt.promise)
    const { result } = renderHook(useAuth, { wrapper })
    const subscription = authHarness.subscriptions[0]
    expect(subscription).toBeDefined()
    act(() => subscription?.next(null))

    // When: Firebase reports a user before that older attempt rejects.
    act(() => subscription?.next(user("current-user")))
    await act(async () => attempt.reject(new Error("obsolete failure")))

    // Then: the obsolete failure cannot replace the authenticated state.
    expect(result.current.state).toMatchObject({ kind: "ready", user: { uid: "current-user" } })
  })

  it("lets only the latest retry report an authentication failure", async () => {
    // Given: the subscription starts one anonymous attempt and retry starts another.
    const firstAttempt = new Deferred<void>()
    const retryAttempt = new Deferred<void>()
    authHarness.attempts.push(firstAttempt.promise, retryAttempt.promise)
    const { result } = renderHook(useAuth, { wrapper })
    const subscription = authHarness.subscriptions[0]
    expect(subscription).toBeDefined()
    act(() => subscription?.next(null))
    act(() => result.current.retry())

    // When: the older attempt rejects before the current retry.
    await act(async () => firstAttempt.reject(new Error("older failure")))

    // Then: only the current retry owns the visible failure state.
    expect(result.current.state.kind).toBe("loading")
    await act(async () => retryAttempt.reject(new Error("current failure")))
    expect(result.current.state.kind).toBe("error")
  })

  it("cleans each StrictMode subscription and ignores its obsolete attempt", async () => {
    // Given: StrictMode mounts two subscription lifetimes with separate attempts.
    const firstAttempt = new Deferred<void>()
    const currentAttempt = new Deferred<void>()
    authHarness.attempts.push(firstAttempt.promise, currentAttempt.promise)
    authHarness.emitNullOnSubscribe = true
    const { result, unmount } = renderHook(useAuth, {
      reactStrictMode: true,
      wrapper: strictWrapper,
    })
    expect(authHarness.subscriptions).toHaveLength(2)
    const firstSubscription = authHarness.subscriptions[0]
    const currentSubscription = authHarness.subscriptions[1]
    expect(firstSubscription).toBeDefined()
    expect(currentSubscription).toBeDefined()

    // When: the cleaned-up lifetime rejects after the current lifetime exists.
    await act(async () => firstAttempt.reject(new Error("cleaned-up failure")))

    // Then: its subscription was released and its attempt cannot own current state.
    expect(firstSubscription?.unsubscribe).toHaveBeenCalledOnce()
    expect(result.current.state.kind).toBe("loading")
    unmount()
    expect(currentSubscription?.unsubscribe).toHaveBeenCalledOnce()
    currentAttempt.resolve(undefined)
  })
})
