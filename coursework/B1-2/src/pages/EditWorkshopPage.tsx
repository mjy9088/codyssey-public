import { useNavigate, useParams } from "react-router-dom"
import { PageHeader } from "../components/PageHeader"
import { ErrorState, LoadingState } from "../components/StateView"
import { WorkshopForm } from "../components/WorkshopForm"
import { useWorkshop } from "../hooks/useWorkshop"
import type { WorkshopInput } from "../lib/workshop"
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
  const save = async (input: WorkshopInput) => {
    await updateWorkshop(state.item.id, input)
    navigate(`/workshops/${state.item.id}`)
  }
  return (
    <div className="route-page">
      <PageHeader title={`Edit ${state.item.title}`}>
        <p>Changes are written directly to the Firestore emulator.</p>
      </PageHeader>
      <WorkshopForm initial={state.item} submitLabel="Save changes" onSubmit={save} />
    </div>
  )
}
