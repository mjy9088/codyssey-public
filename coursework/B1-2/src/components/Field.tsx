import type { InputHTMLAttributes, SelectHTMLAttributes, TextareaHTMLAttributes } from "react"

type Common = {
  readonly label: string
  readonly error?: string | undefined
  readonly hint?: string | undefined
}

const FieldFrame = ({
  id,
  label,
  error,
  hint,
  children,
}: Common & { readonly id: string; readonly children: React.ReactNode }) => (
  <div className="field">
    <label htmlFor={id}>{label}</label>
    {children}
    {hint && !error ? <span className="field__hint">{hint}</span> : null}
    <span className="field__error" id={`${id}-error`}>
      {error ?? ""}
    </span>
  </div>
)

export const InputField = ({
  label,
  error,
  hint,
  id,
  ...props
}: Common & InputHTMLAttributes<HTMLInputElement> & { readonly id: string }) => (
  <FieldFrame id={id} label={label} error={error} hint={hint}>
    <input id={id} aria-invalid={Boolean(error)} aria-describedby={`${id}-error`} {...props} />
  </FieldFrame>
)

export const TextAreaField = ({
  label,
  error,
  hint,
  id,
  ...props
}: Common & TextareaHTMLAttributes<HTMLTextAreaElement> & { readonly id: string }) => (
  <FieldFrame id={id} label={label} error={error} hint={hint}>
    <textarea id={id} aria-invalid={Boolean(error)} aria-describedby={`${id}-error`} {...props} />
  </FieldFrame>
)

export const SelectField = ({
  label,
  error,
  hint,
  id,
  children,
  ...props
}: Common & SelectHTMLAttributes<HTMLSelectElement> & { readonly id: string }) => (
  <FieldFrame id={id} label={label} error={error} hint={hint}>
    <select id={id} aria-invalid={Boolean(error)} aria-describedby={`${id}-error`} {...props}>
      {children}
    </select>
  </FieldFrame>
)
