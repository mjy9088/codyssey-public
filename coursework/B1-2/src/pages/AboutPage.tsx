import { Database, FlowArrow, ShieldCheck } from "@phosphor-icons/react"
import { PageHeader } from "../components/PageHeader"

export const AboutPage = () => (
  <div className="route-page about-page">
    <PageHeader title="How Benchbook is put together">
      <p>The interface is intentionally small enough to make React's data flow inspectable.</p>
    </PageHeader>
    <section className="about-grid">
      <article>
        <FlowArrow aria-hidden="true" />
        <h2>State has an owner</h2>
        <p>
          Forms own draft values. Data hooks own request state. Pages own filters and pagination.
          Shared authentication lives in context.
        </p>
      </article>
      <article>
        <Database aria-hidden="true" />
        <h2>The backend is real</h2>
        <p>
          The Firebase SDK talks to local Auth and Firestore emulators. There is no in-memory
          repository hiding behind the UI.
        </p>
      </article>
      <article>
        <ShieldCheck aria-hidden="true" />
        <h2>Boundaries stay honest</h2>
        <p>
          Docker and QEMU prove local portability. They do not claim a public URL, production
          Firebase project, or cloud deployment.
        </p>
      </article>
    </section>
  </div>
)
