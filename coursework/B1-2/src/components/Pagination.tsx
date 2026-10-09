import { Button } from "./Button"

export const Pagination = ({
  page,
  totalPages,
  onPage,
}: {
  readonly page: number
  readonly totalPages: number
  readonly onPage: (page: number) => void
}) => (
  <nav className="pagination" aria-label="Workshop pages">
    <Button variant="secondary" disabled={page <= 1} onClick={() => onPage(page - 1)}>
      Previous
    </Button>
    <span>
      Page {page} of {totalPages}
    </span>
    <Button variant="secondary" disabled={page >= totalPages} onClick={() => onPage(page + 1)}>
      Next
    </Button>
  </nav>
)
