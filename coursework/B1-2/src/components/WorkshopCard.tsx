import { ArrowRight, MapPin, Users } from "@phosphor-icons/react"
import { Link } from "react-router-dom"
import { formatDate, type Workshop } from "../lib/workshop"
import { Badge } from "./Badge"

export const WorkshopCard = ({ workshop }: { readonly workshop: Workshop }) => (
  <article className="workshop-card">
    <div className="workshop-card__top">
      <Badge status={workshop.status} />
      <time dateTime={workshop.startsAt}>{formatDate(workshop.startsAt)}</time>
    </div>
    <h2>
      <Link to={`/workshops/${workshop.id}`}>{workshop.title}</Link>
    </h2>
    <p>{workshop.summary}</p>
    <div className="workshop-card__meta">
      <span>
        <MapPin aria-hidden="true" />
        {workshop.location}
      </span>
      <span>
        <Users aria-hidden="true" />
        {workshop.capacity} seats
      </span>
    </div>
    <Link className="text-action" to={`/workshops/${workshop.id}`}>
      View workshop <ArrowRight aria-hidden="true" />
    </Link>
  </article>
)
