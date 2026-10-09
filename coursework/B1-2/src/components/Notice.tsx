import type { ReactNode } from "react"

export const Notice = ({
  tone = "info",
  children,
}: {
  readonly tone?: "info" | "success" | "warning" | "danger"
  readonly children: ReactNode
}) => (
  <div className={`notice notice--${tone}`} role={tone === "danger" ? "alert" : "status"}>
    {children}
  </div>
)
