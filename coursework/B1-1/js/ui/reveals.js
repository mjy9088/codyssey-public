/**
 * Initialize one-shot reveal observers for a document region.
 *
 * @param {ParentNode} [root]
 * @returns {() => void}
 */
export function initReveals(root = document) {
  const items = [...root.querySelectorAll(".reveal:not(.is-visible)")];
  if (
    typeof IntersectionObserver === "undefined" ||
    matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    for (const item of items) item.classList.add("is-visible");
    return () => {};
  }

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting || entry.intersectionRatio < 0.2) continue;
        entry.target.classList.remove("is-reveal-pending");
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    },
    { threshold: 0.2 },
  );
  for (const item of items) {
    observer.observe(item);
    item.classList.add("is-reveal-pending");
  }
  return () => {
    observer.disconnect();
    for (const item of items) item.classList.remove("is-reveal-pending");
  };
}
