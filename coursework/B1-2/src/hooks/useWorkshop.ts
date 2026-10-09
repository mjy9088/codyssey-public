import { useCallback, useEffect, useState } from "react"
import { useAuth } from "../context/AuthContext"
import type { Workshop } from "../lib/workshop"
import { getWorkshop } from "../lib/workshop-store"

type WorkshopState =
  | { readonly kind: "loading" }
  | { readonly kind: "error"; readonly message: string }
  | { readonly kind: "missing" }
  | { readonly kind: "ready"; readonly item: Workshop }

export const useWorkshop = (id: string | undefined) => {
  const auth = useAuth()
  const [state, setState] = useState<WorkshopState>({ kind: "loading" })
  const reload = useCallback(async () => {
    if (auth.kind !== "ready" || id === undefined) return
    setState({ kind: "loading" })
    try {
      const item = await getWorkshop(id)
      setState(item ? { kind: "ready", item } : { kind: "missing" })
    } catch (error: unknown) {
      setState({
        kind: "error",
        message: error instanceof Error ? error.message : "Workshop could not be loaded.",
      })
    }
  }, [auth.kind, id])
  useEffect(() => {
    void reload()
  }, [reload])
  return { state, reload }
}
