import { MagnifyingGlass } from "@phosphor-icons/react"
import { useId } from "react"
import type { WorkshopStatus } from "../lib/workshop"

export type StatusFilter = "all" | WorkshopStatus

export const FilterBar = ({
  query,
  status,
  count,
  onQuery,
  onStatus,
}: {
  readonly query: string
  readonly status: StatusFilter
  readonly count: number
  readonly onQuery: (value: string) => void
  readonly onStatus: (value: StatusFilter) => void
}) => {
  const searchId = useId()
  const statusId = useId()
  return (
    <div className="filter-bar">
      <label className="search-field" htmlFor={searchId}>
        <MagnifyingGlass aria-hidden="true" />
        <span className="sr-only">Search workshops</span>
        <input
          id={searchId}
          type="search"
          value={query}
          placeholder="Search title or facilitator"
          onChange={(event) => onQuery(event.currentTarget.value)}
        />
      </label>
      <label className="compact-field" htmlFor={statusId}>
        <span>Status</span>
        <select
          id={statusId}
          value={status}
          onChange={(event) =>
            onStatus(
              event.currentTarget.value === "all"
                ? "all"
                : event.currentTarget.value === "open"
                  ? "open"
                  : event.currentTarget.value === "full"
                    ? "full"
                    : "cancelled",
            )
          }
        >
          <option value="all">All statuses</option>
          <option value="open">Open</option>
          <option value="full">Full</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </label>
      <p aria-live="polite">
        <strong>{count}</strong> result{count === 1 ? "" : "s"}
      </p>
    </div>
  )
}
