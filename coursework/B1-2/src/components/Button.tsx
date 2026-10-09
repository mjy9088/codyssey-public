import type { ButtonHTMLAttributes, ReactNode } from "react"
import { Link } from "react-router-dom"

type Variant = "primary" | "secondary" | "quiet" | "danger"

export const Button = ({
  variant = "primary",
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { readonly variant?: Variant }) => (
  <button className={`button button--${variant}`} {...props}>
    {children}
  </button>
)

export const ButtonLink = ({
  to,
  variant = "primary",
  children,
}: {
  readonly to: string
  readonly variant?: Variant
  readonly children: ReactNode
}) => (
  <Link className={`button button--${variant}`} to={to}>
    {children}
  </Link>
)
