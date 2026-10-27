import { requiredElement } from "./elements.js";

const MOBILE_QUERY = "(max-width: 47.999rem)";

export function initNavigation() {
  const header = requiredElement(document, "#site-header", HTMLElement);
  const menu = requiredElement(document, "#primary-nav", HTMLElement);
  const toggle = requiredElement(document, "#menu-toggle", HTMLButtonElement);
  const backToTop = requiredElement(document, "#back-to-top", HTMLButtonElement);
  const main = requiredElement(document, "#main-content", HTMLElement);

  const label = requiredElement(toggle, ".sr-only", HTMLElement);
  /** @param {boolean} open @param {boolean} [restoreFocus] */
  const setOpen = (open, restoreFocus = false) => {
    toggle.setAttribute("aria-expanded", String(open));
    menu.classList.toggle("is-open", open);
    label.textContent = open ? "Close navigation" : "Open navigation";
    if (restoreFocus) toggle.focus();
  };

  toggle.addEventListener("click", () => setOpen(toggle.getAttribute("aria-expanded") !== "true"));
  menu.addEventListener("click", (event) => {
    const link = event.target instanceof Element ? event.target.closest("a") : null;
    if (!(link instanceof HTMLAnchorElement)) return;
    setOpen(false);
    const target = document.querySelector(link.hash);
    if (target instanceof HTMLElement) {
      target.tabIndex = -1;
      target.focus({ preventScroll: true });
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true")
      setOpen(false, true);
  });
  matchMedia(MOBILE_QUERY).addEventListener("change", (event) => {
    if (!event.matches) setOpen(false);
  });

  const updateViewportState = () => {
    const visible = scrollY > 300;
    header.classList.toggle("is-scrolled", scrollY > 60);
    backToTop.classList.toggle("is-visible", visible);
    backToTop.tabIndex = visible ? 0 : -1;
    backToTop.setAttribute("aria-hidden", String(!visible));
  };
  addEventListener("scroll", updateViewportState, { passive: true });
  updateViewportState();
  backToTop.addEventListener("click", () => {
    main.focus({ preventScroll: true });
    scrollTo({
      top: 0,
      behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
    });
  });
  header.classList.add("navigation-ready");
}
