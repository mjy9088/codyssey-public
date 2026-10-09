import { ButtonLink } from "../components/Button"
import { EmptyState } from "../components/StateView"

export const NotFoundPage = () => (
  <EmptyState
    title="This bench is empty"
    message="The address does not match a Benchbook route."
    action={<ButtonLink to="/workshops">Open the schedule</ButtonLink>}
  />
)
