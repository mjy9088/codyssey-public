const MOBILE_QUERY = "(max-width: 47.999rem)";

export const initNavigation = () => {
  const header = document.querySelector("#site-header");
  const menu = document.querySelector("#primary-nav");
  const toggle = document.querySelector("#menu-toggle");
  const backToTop = document.querySelector("#back-to-top");
  if (!(header instanceof HTMLElement) || !(menu instanceof HTMLElement) || !(toggle instanceof HTMLButtonElement) || !(backToTop instanceof HTMLButtonElement)) return;

  const label = toggle.querySelector(".sr-only");
  const setOpen = (open, restoreFocus = false) => {
    toggle.setAttribute("aria-expanded", String(open));
    menu.classList.toggle("is-open", open);
    if (label) label.textContent = open ? "Close navigation" : "Open navigation";
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
    if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") setOpen(false, true);
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
    const main = document.querySelector("#main-content");
    if (main instanceof HTMLElement) main.focus({ preventScroll: true });
    scrollTo({ top: 0, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  });
};

export const initReveals = (root = document) => {
  const items = [...root.querySelectorAll(".reveal:not(.is-visible)")];
  if (!("IntersectionObserver" in window) || matchMedia("(prefers-reduced-motion: reduce)").matches) {
    items.forEach((item) => item.classList.add("is-visible"));
    return;
  }
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: .2 });
  items.forEach((item) => observer.observe(item));
};
