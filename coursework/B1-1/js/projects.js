import { initReveals } from "./navigation.js";

const API_URL = "https://api.github.com/users/mjy9088/repos?per_page=100&sort=updated";
const REQUEST_TIMEOUT = 8000;
const MAX_PROJECTS = 12;
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
  if (typeof name !== "string" || typeof url !== "string" || typeof updatedAt !== "string" || typeof fork !== "boolean") return null;
  if (!(description === null || typeof description === "string") || !(language === null || typeof language === "string")) return null;
  let parsedUrl;
  try { parsedUrl = new URL(url); } catch { return null; }
  if (parsedUrl.protocol !== "https:" || parsedUrl.hostname !== "github.com" || Number.isNaN(Date.parse(updatedAt))) return null;
  return {
    name: truncate(name, 100),
    url: parsedUrl.href,
    description: description ? truncate(description, 280) : "A public repository without a description yet.",
    language: language ? truncate(language, 32) : "Other",
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
    return payload.map(parseRepo).filter((repo) => repo && !repo.fork).slice(0, MAX_PROJECTS);
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
  date.textContent = new Intl.DateTimeFormat("en", { month: "short", year: "numeric" }).format(new Date(repo.updatedAt));
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

  const render = (language = "all") => {
    list.replaceChildren();
    const visible = language === "all" ? repos : repos.filter((repo) => repo.language === language);
    const cards = visible.map((repo) => cardFor(repo, template)).filter(Boolean);
    list.append(...cards);
    status.textContent = cards.length ? `${cards.length} public ${cards.length === 1 ? "repository" : "repositories"} shown.` : "No repositories match this language.";
    initReveals(list);
  };

  const load = async () => {
    list.innerHTML = LOADING_MARKUP.repeat(3);
    status.textContent = "Loading public repositories…";
    list.setAttribute("aria-busy", "true");
    retry.hidden = true;
    filter.disabled = true;
    try {
      repos = await fetchRepos();
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
