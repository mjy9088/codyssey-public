import { onAuthStateChanged, signInAnonymously, type User } from "firebase/auth"
import { createContext, type ReactNode, useContext, useEffect, useState } from "react"
import { auth } from "../lib/firebase"

type AuthState =
  | { readonly kind: "loading" }
  | { readonly kind: "ready"; readonly user: User }
  | { readonly kind: "error"; readonly message: string }

const AuthContext = createContext<AuthState>({ kind: "loading" })

export const AuthProvider = ({ children }: { readonly children: ReactNode }) => {
  const [state, setState] = useState<AuthState>({ kind: "loading" })
  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      if (user) setState({ kind: "ready", user })
      else
        void signInAnonymously(auth).catch((error: unknown) => {
          setState({
            kind: "error",
            message: error instanceof Error ? error.message : "Authentication failed.",
          })
        })
    })
    return unsubscribe
  }, [])
  return <AuthContext.Provider value={state}>{children}</AuthContext.Provider>
}

export const useAuth = (): AuthState => useContext(AuthContext)
