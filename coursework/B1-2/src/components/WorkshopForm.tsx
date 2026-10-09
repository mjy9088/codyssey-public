import { type FormEvent, useId, useState } from "react"
import { type FieldErrors, parseWorkshopInput, type WorkshopInput } from "../lib/workshop"
import { Button, ButtonLink } from "./Button"
import { InputField, SelectField, TextAreaField } from "./Field"
import { Notice } from "./Notice"

type FormValues = Readonly<Record<keyof WorkshopInput, string>>
const emptyValues: FormValues = {
  title: "",
  summary: "",
  facilitator: "",
  location: "",
  startsAt: "",
  capacity: "12",
  status: "open",
}

export const WorkshopForm = ({
  initial,
  onSubmit,
  submitLabel,
}: {
  readonly initial?: WorkshopInput
  readonly onSubmit: (input: WorkshopInput) => Promise<void>
  readonly submitLabel: string
}) => {
  const formId = useId()
  const [values, setValues] = useState<FormValues>(
    initial ? { ...initial, capacity: String(initial.capacity) } : emptyValues,
  )
  const [errors, setErrors] = useState<FieldErrors>({})
  const [requestError, setRequestError] = useState("")
  const [submitting, setSubmitting] = useState(false)
  const update = (key: keyof WorkshopInput, value: string) => {
    setValues((current) => ({ ...current, [key]: value }))
    setErrors((current) => ({ ...current, [key]: undefined }))
    setRequestError("")
  }
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    const parsed = parseWorkshopInput(values)
    if (!parsed.success) {
      setErrors(parsed.errors)
      return
    }
    setSubmitting(true)
    setRequestError("")
    try {
      await onSubmit(parsed.data)
    } catch (error: unknown) {
      setRequestError(error instanceof Error ? error.message : "The workshop could not be saved.")
    } finally {
      setSubmitting(false)
    }
  }
  return (
    <div className="form-layout">
      <form className="workshop-form" onSubmit={(event) => void submit(event)} noValidate>
        {requestError ? <Notice tone="danger">{requestError}</Notice> : null}
        <InputField
          id={`${formId}-title`}
          label="Workshop title"
          value={values.title}
          error={errors.title}
          required
          onChange={(event) => update("title", event.currentTarget.value)}
        />
        <TextAreaField
          id={`${formId}-summary`}
          label="Summary"
          value={values.summary}
          error={errors.summary}
          rows={4}
          maxLength={240}
          required
          hint="12–240 characters"
          onChange={(event) => update("summary", event.currentTarget.value)}
        />
        <div className="field-row">
          <InputField
            id={`${formId}-facilitator`}
            label="Facilitator"
            value={values.facilitator}
            error={errors.facilitator}
            required
            onChange={(event) => update("facilitator", event.currentTarget.value)}
          />
          <InputField
            id={`${formId}-location`}
            label="Location"
            value={values.location}
            error={errors.location}
            required
            onChange={(event) => update("location", event.currentTarget.value)}
          />
        </div>
        <div className="field-row">
          <InputField
            id={`${formId}-startsAt`}
            label="Start date and time"
            type="datetime-local"
            value={values.startsAt}
            error={errors.startsAt}
            required
            onChange={(event) => update("startsAt", event.currentTarget.value)}
          />
          <InputField
            id={`${formId}-capacity`}
            label="Capacity"
            type="number"
            min="1"
            max="80"
            value={values.capacity}
            error={errors.capacity}
            required
            onChange={(event) => update("capacity", event.currentTarget.value)}
          />
        </div>
        <SelectField
          id={`${formId}-status`}
          label="Status"
          value={values.status}
          error={errors.status}
          onChange={(event) => update("status", event.currentTarget.value)}
        >
          <option value="open">Open</option>
          <option value="full">Full</option>
          <option value="cancelled">Cancelled</option>
        </SelectField>
        <div className="form-actions">
          <Button type="submit" disabled={submitting}>
            {submitting ? "Saving…" : submitLabel}
          </Button>
          <ButtonLink to="/workshops" variant="quiet">
            Cancel
          </ButtonLink>
        </div>
      </form>
      <aside className="form-preview" aria-label="Workshop preview">
        <p className="eyebrow">Live preview</p>
        <h2>{values.title || "Untitled workshop"}</h2>
        <p>{values.summary || "A useful summary will appear here as you type."}</p>
        <dl>
          <div>
            <dt>Facilitator</dt>
            <dd>{values.facilitator || "Not set"}</dd>
          </div>
          <div>
            <dt>Location</dt>
            <dd>{values.location || "Not set"}</dd>
          </div>
          <div>
            <dt>Capacity</dt>
            <dd>{values.capacity || "0"} seats</dd>
          </div>
        </dl>
      </aside>
    </div>
  )
}
