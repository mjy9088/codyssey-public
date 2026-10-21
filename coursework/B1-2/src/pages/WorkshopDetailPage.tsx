import { Calendar, MapPin, PencilSimple, Trash, User, Users } from "@phosphor-icons/react"
import { useState } from "react"
import { useNavigate, useParams } from "react-router-dom"
import { Badge } from "../components/Badge"
import { Button, ButtonLink } from "../components/Button"
import { Notice } from "../components/Notice"
import { ErrorState, LoadingState } from "../components/StateView"
import { useWorkshop } from "../hooks/useWorkshop"
import { formatDate } from "../lib/workshop"
import { removeWorkshop } from "../lib/workshop-store"

export const WorkshopDetailPage = () => {
  const { id } = useParams()
  const { state, reload } = useWorkshop(id)
  const navigate = useNavigate()
  const [confirming, setConfirming] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [deleteError, setDeleteError] = useState("")
  if (state.kind === "loading") return <LoadingState label="Loading workshop" />
  if (state.kind === "error")
    return <ErrorState message={state.message} onRetry={() => void reload()} />
  if (state.kind === "missing")
    return <ErrorState message="This workshop does not exist or was removed." />
  const item = state.item
  const remove = async () => {
    setDeleting(true)
    setDeleteError("")
    try {
      await removeWorkshop(item.id)
      navigate("/workshops", { state: { notice: "Workshop deleted." } })
    } catch {
      setDeleteError("Workshop could not be deleted. Try again.")
    } finally {
      setDeleting(false)
    }
  }
  return (
    <article className="detail-page">
      <div className="detail-page__heading">
        <div>
          <Badge status={item.status} />
          <h1>{item.title}</h1>
          <p>{item.summary}</p>
        </div>
        <div className="detail-page__actions">
          <ButtonLink to={`/workshops/${item.id}/edit`} variant="secondary">
            <PencilSimple aria-hidden="true" />
            Edit
          </ButtonLink>
          <Button
            variant="danger"
            onClick={() => {
              setDeleteError("")
              setConfirming(true)
            }}
          >
            <Trash aria-hidden="true" />
            Delete
          </Button>
        </div>
      </div>
      <dl className="detail-grid">
        <div>
          <dt>
            <Calendar aria-hidden="true" />
            When
          </dt>
          <dd>{formatDate(item.startsAt)}</dd>
        </div>
        <div>
          <dt>
            <MapPin aria-hidden="true" />
            Where
          </dt>
          <dd>{item.location}</dd>
        </div>
        <div>
          <dt>
            <User aria-hidden="true" />
            Facilitator
          </dt>
          <dd>{item.facilitator}</dd>
        </div>
        <div>
          <dt>
            <Users aria-hidden="true" />
            Capacity
          </dt>
          <dd>{item.capacity} participants</dd>
        </div>
      </dl>
      {confirming ? (
        <section className="confirm-panel" aria-label="Delete workshop confirmation">
          <div>
            <h2>Delete this workshop?</h2>
            <p>This removes it from the emulator and cannot be undone.</p>
            {deleteError ? <Notice tone="danger">{deleteError}</Notice> : null}
          </div>
          <div>
            <Button variant="danger" disabled={deleting} onClick={() => void remove()}>
              {deleting ? "Deleting…" : "Delete permanently"}
            </Button>
            <Button
              variant="quiet"
              onClick={() => {
                setDeleteError("")
                setConfirming(false)
              }}
            >
              Keep workshop
            </Button>
          </div>
        </section>
      ) : null}
    </article>
  )
}
