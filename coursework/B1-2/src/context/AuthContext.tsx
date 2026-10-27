import { onAuthStateChanged, signInAnonymously, type User } from "firebase/auth"
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react"
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
  const lifetime = useRef(0)
  const attempt = useRef(0)
  const authenticate = useCallback(() => {
    const lifetimeId = lifetime.current
    const attemptId = ++attempt.current
    setState({ kind: "loading" })
    void signInAnonymously(auth).catch(() => {
      if (lifetime.current !== lifetimeId || attempt.current !== attemptId) return
      setState({
        kind: "error",
        message: "Authentication is unavailable. Try again to reconnect.",
      })
    })
  }, [])
  useEffect(() => {
    const lifetimeId = ++lifetime.current
    const unsubscribe = onAuthStateChanged(
      auth,
      (user) => {
        if (lifetime.current !== lifetimeId) return
        if (user) {
          attempt.current += 1
          setState({ kind: "ready", user })
        } else authenticate()
      },
      () => {
        if (lifetime.current !== lifetimeId) return
        attempt.current += 1
        setState({
          kind: "error",
          message: "Authentication is unavailable. Try again to reconnect.",
        })
      },
    )
    return () => {
      lifetime.current += 1
      attempt.current += 1
      unsubscribe()
    }
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
