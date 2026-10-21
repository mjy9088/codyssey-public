import { useCallback, useEffect, useState } from "react"
import { useAuth } from "../context/AuthContext"
import type { Workshop } from "../lib/workshop"
import { listWorkshops } from "../lib/workshop-store"

export type WorkshopsState =
  | { readonly kind: "loading" }
  | { readonly kind: "error"; readonly message: string }
  | { readonly kind: "ready"; readonly items: readonly Workshop[] }

export const useWorkshops = () => {
  const { state: auth, retry: retryAuth } = useAuth()
  const [state, setState] = useState<WorkshopsState>({ kind: "loading" })
  const reload = useCallback(async () => {
    if (auth.kind === "error") {
      retryAuth()
      return
    }
    if (auth.kind === "loading") return
    setState({ kind: "loading" })
    try {
      setState({ kind: "ready", items: await listWorkshops() })
    } catch {
      setState({
        kind: "error",
        message: "Workshops could not be loaded.",
      })
    }
  }, [auth.kind, retryAuth])
  useEffect(() => {
    if (auth.kind === "error") {
      setState({ kind: "error", message: auth.message })
    } else if (auth.kind === "ready") {
      void reload()
    }
  }, [auth, reload])
  return { state, reload }
}
