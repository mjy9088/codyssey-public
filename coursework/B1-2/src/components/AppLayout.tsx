import { BookOpen, Info, Plus, Wrench } from "@phosphor-icons/react"
import { useId } from "react"
import { NavLink, Outlet } from "react-router-dom"
import { useAuth } from "../context/AuthContext"

export const AppLayout = () => {
  const { state: auth } = useAuth()
  const mainId = useId()
  return (
    <div className="app-shell">
      <a
        className="skip-link"
        href={`#${mainId}`}
        onClick={(event) => {
          event.preventDefault()
          const main = document.getElementById(mainId)
          main?.focus()
          main?.scrollIntoView()
        }}
      >
        Skip to main content
      </a>
      <header className="site-header">
        <div className="site-header__inner">
          <NavLink className="brand" to="/">
            <span className="brand__mark" aria-hidden="true">
              B
            </span>
            <span>
              Benchbook<small>workshop planner</small>
            </span>
          </NavLink>
          <nav aria-label="Primary navigation">
            <NavLink to="/workshops">
              <Wrench aria-hidden="true" />
              Workshops
            </NavLink>
            <NavLink to="/workshops/new">
              <Plus aria-hidden="true" />
              Add
            </NavLink>
            <NavLink to="/about">
              <Info aria-hidden="true" />
              About
            </NavLink>
          </nav>
          <span className={`auth-mark auth-mark--${auth.kind}`}>
            {auth.kind === "ready"
              ? "Signed in"
              : auth.kind === "error"
                ? "Auth unavailable"
                : "Connecting"}
          </span>
        </div>
      </header>
      <main id={mainId} className="page-shell" tabIndex={-1}>
        <Outlet />
      </main>
      <footer>
        <div className="footer-inner">
          <p>
            <BookOpen aria-hidden="true" /> Benchbook
          </p>
          <p>React state, Firebase data, honest boundaries.</p>
        </div>
      </footer>
    </div>
  )
}
