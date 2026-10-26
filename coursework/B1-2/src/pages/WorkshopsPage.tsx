import { useMemo, useState } from "react"
import { Button, ButtonLink } from "../components/Button"
import { FilterBar, type StatusFilter } from "../components/FilterBar"
import { Notice } from "../components/Notice"
import { PageHeader } from "../components/PageHeader"
import { Pagination } from "../components/Pagination"
import { EmptyState, ErrorState, LoadingState } from "../components/StateView"
import { WorkshopCard } from "../components/WorkshopCard"
import { useWorkshops } from "../hooks/useWorkshops"
import { seedWorkshops } from "../lib/workshop-seed"

const pageSize = 4

export const WorkshopsPage = () => {
  const { state, reload } = useWorkshops()
  const [query, setQuery] = useState("")
  const [status, setStatus] = useState<StatusFilter>("all")
  const [page, setPage] = useState(1)
  const [seeding, setSeeding] = useState(false)
  const [seedError, setSeedError] = useState("")
  const filtered = useMemo(
    () =>
      state.kind === "ready"
        ? state.items.filter((item) => {
            const matchesQuery = `${item.title} ${item.facilitator}`
              .toLowerCase()
              .includes(query.toLowerCase())
            return matchesQuery && (status === "all" || item.status === status)
          })
        : [],
    [query, state, status],
  )
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const visible = filtered.slice(
    (Math.min(page, totalPages) - 1) * pageSize,
    Math.min(page, totalPages) * pageSize,
  )
  const loadSamples = async () => {
    setSeeding(true)
    setSeedError("")
    try {
      await seedWorkshops()
      await reload()
    } catch {
      setSeedError("Sample schedule could not be loaded. Try again.")
    } finally {
      setSeeding(false)
    }
  }
  return (
    <div className="route-page">
      <PageHeader
        title="Workshop schedule"
        actions={<ButtonLink to="/workshops/new">Add workshop</ButtonLink>}
      >
        <p>Search the bench, check capacity, and keep the schedule current.</p>
      </PageHeader>
      {state.kind === "loading" ? <LoadingState /> : null}
      {state.kind === "error" ? (
        <ErrorState message={state.message} onRetry={() => void reload()} />
      ) : null}
      {state.kind === "ready" && state.items.length === 0 ? (
        <>
          {seedError ? <Notice tone="danger">{seedError}</Notice> : null}
          <EmptyState
            title="The schedule is clear"
            message="Load deterministic sample workshops or add the first session."
            action={
              <div className="state-actions">
                <Button onClick={() => void loadSamples()} disabled={seeding}>
                  {seeding ? "Loading…" : "Load sample schedule"}
                </Button>
                <ButtonLink to="/workshops/new" variant="secondary">
                  Add one manually
                </ButtonLink>
              </div>
            }
          />
        </>
      ) : null}
      {state.kind === "ready" && state.items.length > 0 ? (
        <>
          <FilterBar
            query={query}
            status={status}
            count={filtered.length}
            onQuery={(value) => {
              setQuery(value)
              setPage(1)
            }}
            onStatus={(value) => {
              setStatus(value)
              setPage(1)
            }}
          />
          {visible.length ? (
            <div className="workshop-grid">
              {visible.map((item) => (
                <WorkshopCard key={item.id} workshop={item} />
              ))}
            </div>
          ) : (
            <EmptyState
              title="No matching workshops"
              message="Change the search or status filter to widen the schedule."
            />
          )}
          <Pagination page={Math.min(page, totalPages)} totalPages={totalPages} onPage={setPage} />
        </>
      ) : null}
    </div>
  )
}
