import type { ReactNode } from "react"

export const PageHeader = ({
  eyebrow,
  title,
  children,
  actions,
}: {
  readonly eyebrow?: string
  readonly title: string
  readonly children?: ReactNode
  readonly actions?: ReactNode
}) => (
  <header className="page-header">
    <div>
      {eyebrow ? <p className="eyebrow">{eyebrow}</p> : null}
      <h1>{title}</h1>
      {children ? <div className="page-header__copy">{children}</div> : null}
    </div>
    {actions ? <div className="page-header__actions">{actions}</div> : null}
  </header>
)
