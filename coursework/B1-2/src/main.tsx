import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./App"
import "./styles/tokens.css"
import "./styles/base.css"
import "./styles/components.css"
import "./styles/pages.css"

if (import.meta.env.DEV && import.meta.env.VITE_DISABLE_REACT_DEVTOOLS !== "1") {
  void import("react-grab")
  void import("react-scan")
}

const root = document.querySelector("#root")
if (!(root instanceof HTMLElement)) throw new TypeError("Missing #root element")
createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
