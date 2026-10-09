import { useCallback, useEffect, useState } from "react"
import { useAuth } from "../context/AuthContext"
import type { Workshop } from "../lib/workshop"
import { listWorkshops } from "../lib/workshop-store"

export type WorkshopsState =
  | { readonly kind: "loading" }
  | { readonly kind: "error"; readonly message: string }
  | { readonly kind: "ready"; readonly items: readonly Workshop[] }

export const useWorkshops = () => {
  const auth = useAuth()
  const [state, setState] = useState<WorkshopsState>({ kind: "loading" })
  const reload = useCallback(async () => {
    if (auth.kind !== "ready") return
    setState({ kind: "loading" })
    try {
      setState({ kind: "ready", items: await listWorkshops() })
    } catch {
      setState({
        kind: "error",
        message: "Workshops could not be loaded.",
      })
    }
  }, [auth.kind])
  useEffect(() => {
    void reload()
  }, [reload])
  return { state, reload }
}
