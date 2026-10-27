import type { User } from "firebase/auth"
import { useCallback, useEffect, useRef, useState } from "react"
import { useAuth } from "../context/AuthContext"
import type { Workshop } from "../lib/workshop"
import { listWorkshops } from "../lib/workshop-store"

export type WorkshopsState =
  | { readonly kind: "loading" }
  | { readonly kind: "error"; readonly message: string }
  | { readonly kind: "ready"; readonly items: readonly Workshop[] }

type OwnedWorkshopsState = {
  readonly user: User
  readonly state: WorkshopsState
}

export const useWorkshops = () => {
  const { state: auth, retry: retryAuth } = useAuth()
  const [ownedState, setOwnedState] = useState<OwnedWorkshopsState>()
  const mounted = useRef(false)
  const request = useRef(0)
  const reload = useCallback(async () => {
    if (auth.kind === "error") {
      retryAuth()
      return
    }
    if (auth.kind === "loading") return
    const requestId = ++request.current
    const owner = auth.user
    setOwnedState({ user: owner, state: { kind: "loading" } })
    try {
      const items = await listWorkshops()
      if (!mounted.current || request.current !== requestId) return
      setOwnedState({ user: owner, state: { kind: "ready", items } })
    } catch {
      if (!mounted.current || request.current !== requestId) return
      setOwnedState({
        user: owner,
        state: {
          kind: "error",
          message: "Workshops could not be loaded.",
        },
      })
    }
  }, [auth, retryAuth])
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
      request.current += 1
    }
  }, [])
  useEffect(() => {
    request.current += 1
    if (auth.kind === "ready") void reload()
  }, [auth, reload])
  const state: WorkshopsState =
    auth.kind === "error"
      ? { kind: "error", message: auth.message }
      : auth.kind === "loading"
        ? { kind: "loading" }
        : ownedState?.user === auth.user
          ? ownedState.state
          : { kind: "loading" }
  return { state, reload }
}
