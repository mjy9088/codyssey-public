import { WarningCircle, Wrench } from "@phosphor-icons/react"
import { Button } from "./Button"

export const LoadingState = ({ label = "Loading workshops" }: { readonly label?: string }) => (
  <output className="state-view" aria-live="polite">
    <div className="skeleton" aria-hidden="true">
      <span />
      <span />
      <span />
    </div>
    <span>{label}…</span>
  </output>
)

export const EmptyState = ({
  title,
  message,
  action,
}: {
  readonly title: string
  readonly message: string
  readonly action?: React.ReactNode
}) => (
  <section className="state-view state-view--empty">
    <Wrench size={28} aria-hidden="true" />
    <h2>{title}</h2>
    <p>{message}</p>
    {action}
  </section>
)

export const ErrorState = ({
  message,
  onRetry,
}: {
  readonly message: string
  readonly onRetry?: () => void
}) => (
  <section className="state-view state-view--error" role="alert">
    <WarningCircle size={28} aria-hidden="true" />
    <h2>Something needs attention</h2>
    <p>{message}</p>
    {onRetry ? (
      <Button variant="secondary" onClick={onRetry}>
        Try again
      </Button>
    ) : null}
  </section>
)
