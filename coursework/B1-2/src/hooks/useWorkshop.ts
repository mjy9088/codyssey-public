import type { User } from "firebase/auth"
import { useCallback, useEffect, useRef, useState } from "react"
import { useAuth } from "../context/AuthContext"
import type { Workshop } from "../lib/workshop"
import { getWorkshop } from "../lib/workshop-store"

type WorkshopState =
  | { readonly kind: "loading" }
  | { readonly kind: "error"; readonly message: string }
  | { readonly kind: "missing" }
  | { readonly kind: "ready"; readonly item: Workshop }

type OwnedWorkshopState = {
  readonly user: User
  readonly id: string
  readonly state: WorkshopState
}

export const useWorkshop = (id: string | undefined) => {
  const { state: auth, retry: retryAuth } = useAuth()
  const [ownedState, setOwnedState] = useState<OwnedWorkshopState>()
  const mounted = useRef(false)
  const request = useRef(0)
  const reload = useCallback(async () => {
    if (auth.kind === "error") {
      retryAuth()
      return
    }
    if (auth.kind === "loading" || id === undefined) return
    const requestId = ++request.current
    const owner = { user: auth.user, id }
    setOwnedState({ ...owner, state: { kind: "loading" } })
    try {
      const item = await getWorkshop(id)
      if (!mounted.current || request.current !== requestId) return
      setOwnedState({
        ...owner,
        state: item ? { kind: "ready", item } : { kind: "missing" },
      })
    } catch (error: unknown) {
      if (!mounted.current || request.current !== requestId) return
      setOwnedState({
        ...owner,
        state: {
          kind: "error",
          message: error instanceof Error ? error.message : "Workshop could not be loaded.",
        },
      })
    }
  }, [auth, id, retryAuth])
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
  const state: WorkshopState =
    auth.kind === "error"
      ? { kind: "error", message: auth.message }
      : auth.kind === "loading" || id === undefined
        ? { kind: "loading" }
        : ownedState?.user === auth.user && ownedState.id === id
          ? ownedState.state
          : { kind: "loading" }
  return { state, reload }
}
