import { FirebaseError } from "firebase/app"

export type AuthFailureReason =
  | "configuration"
  | "anonymous-disabled"
  | "client-settings"
  | "unavailable"

export const classifyAuthFailure = (error: unknown): AuthFailureReason => {
  if (!(error instanceof FirebaseError)) return "unavailable"
  switch (error.code) {
    case "auth/configuration-not-found":
      return "configuration"
    case "auth/operation-not-allowed":
      return "anonymous-disabled"
    case "auth/invalid-api-key":
    case "auth/app-not-authorized":
    case "auth/unauthorized-domain":
      return "client-settings"
    default:
      return "unavailable"
  }
}
