import { ArrowRight, CalendarCheck, ListMagnifyingGlass, PencilSimple } from "@phosphor-icons/react"
import { ButtonLink } from "../components/Button"

export const HomePage = () => (
  <div className="home-page">
    <section className="hero">
      <div>
        <p className="eyebrow">A small studio ledger</p>
        <h1>Make room for useful work.</h1>
        <p className="hero__lead">
          Plan hands-on workshops, keep every state visible, and let a real local Firebase emulator
          hold the schedule.
        </p>
        <div className="hero__actions">
          <ButtonLink to="/workshops">
            Browse workshops <ArrowRight aria-hidden="true" />
          </ButtonLink>
          <ButtonLink to="/workshops/new" variant="quiet">
            Add a workshop
          </ButtonLink>
        </div>
      </div>
      <section className="hero-ledger" aria-label="Planning flow">
        <span>01</span>
        <div>
          <CalendarCheck aria-hidden="true" />
          <strong>Schedule</strong>
          <small>Time, place, and capacity</small>
        </div>
        <span>02</span>
        <div>
          <PencilSimple aria-hidden="true" />
          <strong>Refine</strong>
          <small>Controlled forms and validation</small>
        </div>
        <span>03</span>
        <div>
          <ListMagnifyingGlass aria-hidden="true" />
          <strong>Find</strong>
          <small>Filter, page, and inspect</small>
        </div>
      </section>
    </section>
    <section className="principles">
      <h2>Designed around state, not screenshots.</h2>
      <div>
        <article>
          <strong>One data source</strong>
          <p>Every create, edit, and delete reaches Firestore through the official SDK.</p>
        </article>
        <article>
          <strong>Failure is visible</strong>
          <p>Loading, empty, error, invalid, and submitting states share a consistent language.</p>
        </article>
        <article>
          <strong>Routes stay useful</strong>
          <p>Seven routes cover discovery, detail, authoring, editing, context, and recovery.</p>
        </article>
      </div>
    </section>
  </div>
)
