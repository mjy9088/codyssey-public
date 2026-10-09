import { useNavigate } from "react-router-dom"
import { PageHeader } from "../components/PageHeader"
import { WorkshopForm } from "../components/WorkshopForm"
import type { WorkshopInput } from "../lib/workshop"
import { createWorkshop } from "../lib/workshop-store"

export const NewWorkshopPage = () => {
  const navigate = useNavigate()
  const create = async (input: WorkshopInput) => {
    const id = await createWorkshop(input)
    navigate(`/workshops/${id}`)
  }
  return (
    <div className="route-page">
      <PageHeader title="Add a workshop">
        <p>Set a clear promise, then give participants the practical details.</p>
      </PageHeader>
      <WorkshopForm submitLabel="Create workshop" onSubmit={create} />
    </div>
  )
}
