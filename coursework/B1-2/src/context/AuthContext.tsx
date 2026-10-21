import { onAuthStateChanged, signInAnonymously, type User } from "firebase/auth"
import { createContext, type ReactNode, useCallback, useContext, useEffect, useState } from "react"
import { auth } from "../lib/firebase"

type AuthState =
  | { readonly kind: "loading" }
  | { readonly kind: "ready"; readonly user: User }
  | { readonly kind: "error"; readonly message: string }

type AuthValue = {
  readonly state: AuthState
  readonly retry: () => void
}

const AuthContext = createContext<AuthValue | undefined>(undefined)

export const AuthProvider = ({ children }: { readonly children: ReactNode }) => {
  const [state, setState] = useState<AuthState>({ kind: "loading" })
  const authenticate = useCallback(() => {
    setState({ kind: "loading" })
    void signInAnonymously(auth).catch(() => {
      setState({
        kind: "error",
        message: "Authentication is unavailable. Try again to reconnect.",
      })
    })
  }, [])
  useEffect(() => {
    const unsubscribe = onAuthStateChanged(
      auth,
      (user) => {
        if (user) setState({ kind: "ready", user })
        else authenticate()
      },
      () => {
        setState({
          kind: "error",
          message: "Authentication is unavailable. Try again to reconnect.",
        })
      },
    )
    return unsubscribe
  }, [authenticate])
  return (
    <AuthContext.Provider value={{ state, retry: authenticate }}>{children}</AuthContext.Provider>
  )
}

export const useAuth = (): AuthValue => {
  const value = useContext(AuthContext)
  if (value === undefined) throw new Error("useAuth must be used within AuthProvider.")
  return value
}
