import react from "@vitejs/plugin-react"
import { loadEnv } from "vite"
import { defineConfig } from "vitest/config"

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), "VITE_")
  if (command === "build" && env.VITE_USE_EMULATORS === "false") {
    for (const name of [
      "VITE_FIREBASE_API_KEY",
      "VITE_FIREBASE_AUTH_DOMAIN",
      "VITE_FIREBASE_PROJECT_ID",
    ]) {
      if (!env[name]?.trim()) throw new Error(`Remote Firebase build requires ${name}`)
    }
  }
  return {
    plugins: [react()],
    server: { port: 5173 },
    preview: { port: 4173 },
    test: { environment: "jsdom", globals: true, include: ["tests/**/*.test.ts"] },
  }
})
