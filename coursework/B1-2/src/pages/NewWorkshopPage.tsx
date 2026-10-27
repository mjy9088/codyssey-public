import { useNavigate } from "react-router-dom"
import { PageHeader } from "../components/PageHeader"
import { ErrorState, LoadingState } from "../components/StateView"
import { WorkshopForm } from "../components/WorkshopForm"
import { useAuth } from "../context/AuthContext"
import { createWorkshop } from "../lib/workshop-store"

export const NewWorkshopPage = () => {
  const navigate = useNavigate()
  const { state: auth, retry } = useAuth()
  if (auth.kind === "loading") return <LoadingState label="Preparing workshop form" />
  if (auth.kind === "error") return <ErrorState message={auth.message} onRetry={retry} />
  return (
    <div className="route-page">
      <PageHeader title="Add a workshop">
        <p>Set a clear promise, then give participants the practical details.</p>
      </PageHeader>
      <WorkshopForm
        submitLabel="Create workshop"
        onSubmit={createWorkshop}
        onSaved={(id) => navigate(`/workshops/${encodeURIComponent(id)}`)}
      />
    </div>
  )
}
