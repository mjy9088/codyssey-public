import type { WorkshopStatus } from "../lib/workshop"

export const Badge = ({ status }: { readonly status: WorkshopStatus }) => (
  <span className={`badge badge--${status}`}>{status}</span>
)
