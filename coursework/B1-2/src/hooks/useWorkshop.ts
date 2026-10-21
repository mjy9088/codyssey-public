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
  const { state: auth, retry: retryAuth } = useAuth()
  const [state, setState] = useState<WorkshopState>({ kind: "loading" })
  const reload = useCallback(async () => {
    if (auth.kind === "error") {
      retryAuth()
      return
    }
    if (auth.kind === "loading" || id === undefined) return
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
  }, [auth.kind, id, retryAuth])
  useEffect(() => {
    if (auth.kind === "error") {
      setState({ kind: "error", message: auth.message })
    } else if (auth.kind === "ready") {
      void reload()
    }
  }, [auth, reload])
  return { state, reload }
}
