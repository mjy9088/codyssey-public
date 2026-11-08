import { useNavigate, useParams } from "react-router-dom"
import { PageHeader } from "../components/PageHeader"
import { ErrorState, LoadingState } from "../components/StateView"
import { WorkshopForm } from "../components/WorkshopForm"
import { useWorkshop } from "../hooks/useWorkshop"
import type { WorkshopId, WorkshopInput } from "../lib/workshop"
import { updateWorkshop } from "../lib/workshop-store"

export const EditWorkshopPage = () => {
  const { id } = useParams()
  const { state, reload } = useWorkshop(id)
  const navigate = useNavigate()
  if (state.kind === "loading") return <LoadingState label="Loading form" />
  if (state.kind === "error")
    return <ErrorState message={state.message} onRetry={() => void reload()} />
  if (state.kind === "missing")
    return <ErrorState message="This workshop does not exist or was removed." />
  const save = async (input: WorkshopInput): Promise<WorkshopId> => {
    await updateWorkshop(state.item.id, input)
    return state.item.id
  }
  return (
    <div className="route-page">
      <PageHeader title={`Edit ${state.item.title}`}>
        <p>Changes are written directly to Firestore.</p>
      </PageHeader>
      <WorkshopForm
        initial={state.item}
        submitLabel="Save changes"
        onSubmit={save}
        onSaved={(id) => navigate(`/workshops/${encodeURIComponent(id)}`)}
      />
    </div>
  )
}
