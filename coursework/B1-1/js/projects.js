import { initReveals } from "./navigation.js";

const API_URL = "https://api.github.com/users/mjy9088/repos?per_page=100&sort=updated";
const REQUEST_TIMEOUT = 8000;
const MAX_REPOSITORIES = 100;
const MAX_PROJECTS = 12;
const dateFormatter = new Intl.DateTimeFormat("en", { month: "short", year: "numeric", timeZone: "UTC" });
const LOADING_MARKUP = '<div class="project-skeleton" aria-hidden="true"><span></span><span></span><span></span></div>';
const truncate = (text, length) => [...text.trim()].slice(0, length).join("");
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

const parseRepo = (value) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const { name, html_url: url, description, language, updated_at: updatedAt, fork } = value;
  if (typeof name !== "string" || !name.trim() || typeof url !== "string" || typeof updatedAt !== "string" || typeof fork !== "boolean") return null;
  if (!(description === null || typeof description === "string") || !(language === null || typeof language === "string")) return null;
  let parsedUrl;
  try { parsedUrl = new URL(url); } catch { return null; }
  if (parsedUrl.origin !== "https://github.com" || parsedUrl.username || parsedUrl.password || Number.isNaN(Date.parse(updatedAt))) return null;
  return {
    name: truncate(name, 100),
    url: parsedUrl.href,
    description: description?.trim() ? truncate(description, 280) : "A public repository without a description yet.",
    language: language?.trim() ? truncate(language, 32) : "Other",
    updatedAt,
    fork,
  };
};

const fetchRepos = async () => {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT);
  try {
    const response = await fetch(API_URL, { headers: { Accept: "application/vnd.github+json" }, signal: controller.signal });
    if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
    const payload = await response.json();
    if (!Array.isArray(payload)) throw new TypeError("GitHub response was not a repository list");
    const parsed = payload.slice(0, MAX_REPOSITORIES).map(parseRepo);
    const rejected = parsed.filter((repo) => repo === null).length;
    const repos = parsed.filter((repo) => repo !== null && !repo.fork).slice(0, MAX_PROJECTS);
    if (!repos.length && rejected) throw new TypeError("GitHub returned no usable non-fork repositories");
    return { repos, rejected };
  } finally {
    window.clearTimeout(timeout);
  }
};

const cardFor = (repo, template) => {
  const fragment = template.content.cloneNode(true);
  const card = fragment.querySelector(".project-card");
  const language = fragment.querySelector(".project-language");
  const date = fragment.querySelector(".project-date");
  const name = fragment.querySelector(".project-name");
  const description = fragment.querySelector(".project-description");
  const link = fragment.querySelector(".project-link");
  if (!(card instanceof HTMLElement) || !(language instanceof HTMLElement) || !(date instanceof HTMLElement) || !(name instanceof HTMLElement) || !(description instanceof HTMLElement) || !(link instanceof HTMLAnchorElement)) return null;
  language.textContent = repo.language;
  date.textContent = dateFormatter.format(new Date(repo.updatedAt));
  name.textContent = repo.name;
  description.textContent = repo.description;
  link.href = repo.url;
  link.setAttribute("aria-label", `View ${repo.name} repository on GitHub`);
  card.dataset.language = repo.language;
  return card;
};

export const initProjects = () => {
  const list = document.querySelector("#project-list");
  const status = document.querySelector("#projects-status");
  const retry = document.querySelector("#project-retry");
  const filter = document.querySelector("#project-filter");
  if (!(list instanceof HTMLElement) || !(status instanceof HTMLElement) || !(retry instanceof HTMLButtonElement) || !(filter instanceof HTMLSelectElement)) return;
  const template = document.createElement("template");
  template.innerHTML = PROJECT_CARD_MARKUP;
  let repos = [];
  let rejected = 0;
  let stopReveals = () => {};

  const render = (language = "all") => {
    stopReveals();
    list.replaceChildren();
    const visible = language === "all" ? repos : repos.filter((repo) => repo.language === language);
    const cards = visible.map((repo) => cardFor(repo, template)).filter(Boolean);
    list.append(...cards);
    status.textContent = cards.length ? `${cards.length} public ${cards.length === 1 ? "repository" : "repositories"} shown.` : "No repositories match this language.";
    if (rejected) status.textContent += ` ${rejected} invalid ${rejected === 1 ? "record" : "records"} skipped.`;
    stopReveals = initReveals(list);
  };

  const load = async () => {
    stopReveals();
    list.innerHTML = LOADING_MARKUP.repeat(3);
    status.textContent = "Loading public repositories…";
    list.setAttribute("aria-busy", "true");
    retry.hidden = true;
    filter.disabled = true;
    try {
      ({ repos, rejected } = await fetchRepos());
      list.replaceChildren();
      if (!repos.length) {
        status.textContent = "No public repositories are available right now.";
        return;
      }
      const languages = [...new Set(repos.map((repo) => repo.language))].sort();
      const options = languages.map((language) => {
        const option = document.createElement("option");
        option.value = language;
        option.textContent = language;
        return option;
      });
      filter.replaceChildren(new Option("All languages", "all"), ...options);
      filter.disabled = false;
      render();
    } catch (error) {
      list.replaceChildren();
      status.textContent = error instanceof DOMException && error.name === "AbortError" ? "GitHub took too long to respond." : "Public repositories could not be loaded.";
      retry.hidden = false;
    } finally {
      list.setAttribute("aria-busy", "false");
    }
  };

  filter.addEventListener("change", () => render(filter.value));
  retry.addEventListener("click", load);
  load();
};
