import { ProjectLoadError } from "../domain/project-load.js";
import { filterRepositories, listLanguages } from "../domain/projects.js";
import { requiredElement } from "./elements.js";

const dateFormatter = new Intl.DateTimeFormat("en", {
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});
const LOADING_MARKUP =
  '<div class="project-skeleton" aria-hidden="true"><span></span><span></span><span></span></div>';
const PROJECT_CARD_MARKUP = `
  <article class="project-card reveal">
    <div class="project-meta">
      <span class="project-language"></span>
      <span class="project-date"></span>
    </div>
    <h3 class="project-name"></h3>
    <p class="project-description"></p>
    <a class="text-link project-link" target="_blank" rel="noreferrer">
      View repository <span aria-hidden="true">↗</span>
    </a>
  </article>`;

/** @typedef {import("../domain/projects.js").Repository} Repository */
/** @typedef {import("../domain/projects.js").RepositorySelection} RepositorySelection */
/** @typedef {() => Promise<RepositorySelection>} RepositoryLoader */
/** @typedef {(root?: ParentNode) => () => void} RevealInitializer */

/** @param {Repository} repository @param {HTMLTemplateElement} template @returns {HTMLElement} */
function cardFor(repository, template) {
  const fragment = template.content.cloneNode(true);
  if (!(fragment instanceof DocumentFragment))
    throw new TypeError("Project template did not produce a document fragment");
  const card = requiredElement(fragment, ".project-card", HTMLElement);
  const language = requiredElement(fragment, ".project-language", HTMLElement);
  const date = requiredElement(fragment, ".project-date", HTMLElement);
  const name = requiredElement(fragment, ".project-name", HTMLElement);
  const description = requiredElement(fragment, ".project-description", HTMLElement);
  const link = requiredElement(fragment, ".project-link", HTMLAnchorElement);

  language.textContent = repository.language;
  date.textContent = dateFormatter.format(new Date(repository.updatedAt));
  name.textContent = repository.name;
  description.textContent =
    repository.description ?? "A public repository without a description yet.";
  link.href = repository.url;
  link.setAttribute("aria-label", `View ${repository.name} repository on GitHub`);
  card.dataset.language = repository.language;
  return card;
}

/** @param {{ loadRepositories: RepositoryLoader, startReveals: RevealInitializer }} dependencies */
export function initProjects({ loadRepositories, startReveals }) {
  const list = requiredElement(document, "#project-list", HTMLElement);
  const status = requiredElement(document, "#projects-status", HTMLElement);
  const retry = requiredElement(document, "#project-retry", HTMLButtonElement);
  const filter = requiredElement(document, "#project-filter", HTMLSelectElement);
  status.tabIndex = -1;

  const template = document.createElement("template");
  template.innerHTML = PROJECT_CARD_MARKUP;
  /** @type {Repository[]} */
  let repositories = [];
  let rejected = 0;
  let stopReveals = () => {};

  /** @param {string} [language] */
  const render = (language = "all") => {
    stopReveals();
    list.replaceChildren();
    const visible = filterRepositories(repositories, language);
    const cards = visible.map((repository) => cardFor(repository, template));
    list.append(...cards);
    status.textContent = cards.length
      ? `${cards.length} public ${cards.length === 1 ? "repository" : "repositories"} shown.`
      : "No repositories match this language.";
    if (rejected)
      status.textContent += ` ${rejected} invalid ${rejected === 1 ? "record" : "records"} skipped.`;
    stopReveals = startReveals(list);
  };

  /** @param {boolean} [userInitiated] */
  const load = async (userInitiated = false) => {
    stopReveals();
    list.innerHTML = LOADING_MARKUP.repeat(3);
    status.textContent = "Loading public repositories…";
    list.setAttribute("aria-busy", "true");
    if (userInitiated) status.focus({ preventScroll: true });
    retry.hidden = true;
    filter.disabled = true;
    try {
      ({ repositories, rejected } = await loadRepositories());
      list.replaceChildren();
      if (!repositories.length) {
        status.textContent = "No public repositories are available right now.";
        return;
      }
      const options = listLanguages(repositories).map((language) => new Option(language, language));
      filter.replaceChildren(new Option("All languages", "all"), ...options);
      filter.disabled = false;
      render();
      if (userInitiated && document.activeElement === status) filter.focus({ preventScroll: true });
    } catch (error) {
      if (!(error instanceof ProjectLoadError)) throw error;
      repositories = [];
      rejected = 0;
      list.replaceChildren();
      status.textContent =
        error.kind === "timeout"
          ? "GitHub took too long to respond."
          : "Public repositories could not be loaded.";
      retry.hidden = false;
      if (userInitiated && document.activeElement === status) retry.focus({ preventScroll: true });
    } finally {
      list.setAttribute("aria-busy", "false");
    }
  };

  filter.addEventListener("change", () => render(filter.value));
  retry.addEventListener("click", () => {
    void load(true);
  });
  void load();
}
