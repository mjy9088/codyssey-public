const MAX_REPOSITORY_INPUTS = 100;
const MAX_SELECTED_PROJECTS = 12;

const DEFAULT_LANGUAGE = "Other";

/**
 * @typedef {object} Repository
 * @property {string} name
 * @property {string} url
 * @property {string | null} description
 * @property {string} language
 * @property {string} updatedAt
 * @property {boolean} fork
 */

/**
 * @typedef {object} RepositorySelection
 * @property {Repository[]} repositories
 * @property {number} rejected
 */

export class InvalidRepositoryDataError extends TypeError {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "InvalidRepositoryDataError";
  }
}

/** @param {string} text @param {number} length */
function truncate(text, length) {
  return [...text.trim()].slice(0, length).join("");
}

/** @param {unknown} value @returns {Repository | null} */
function normalizeRepository(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  if (
    !("name" in value) ||
    !("html_url" in value) ||
    !("description" in value) ||
    !("language" in value) ||
    !("updated_at" in value) ||
    !("fork" in value)
  )
    return null;

  const name = value.name;
  const url = value.html_url;
  const description = value.description;
  const language = value.language;
  const updatedAt = value.updated_at;
  const fork = value.fork;
  if (
    typeof name !== "string" ||
    !name.trim() ||
    typeof url !== "string" ||
    typeof updatedAt !== "string" ||
    typeof fork !== "boolean"
  )
    return null;
  if (
    !(description === null || typeof description === "string") ||
    !(language === null || typeof language === "string")
  )
    return null;

  let parsedUrl;
  try {
    parsedUrl = new URL(url);
  } catch {
    return null;
  }
  if (
    parsedUrl.origin !== "https://github.com" ||
    parsedUrl.username ||
    parsedUrl.password ||
    Number.isNaN(Date.parse(updatedAt))
  )
    return null;

  return {
    name: truncate(name, 100),
    url: parsedUrl.href,
    description: description?.trim() ? truncate(description, 280) : null,
    language: language?.trim() ? truncate(language, 32) : DEFAULT_LANGUAGE,
    updatedAt,
    fork,
  };
}

/** @param {unknown} payload @returns {RepositorySelection} */
export function selectRepositories(payload) {
  if (!Array.isArray(payload))
    throw new InvalidRepositoryDataError("GitHub response was not a repository list");
  const parsed = payload.slice(0, MAX_REPOSITORY_INPUTS).map(normalizeRepository);
  const rejected = parsed.filter((repository) => repository === null).length;
  const repositories = parsed
    .filter((repository) => repository !== null)
    .filter((repository) => !repository.fork)
    .slice(0, MAX_SELECTED_PROJECTS);
  if (!repositories.length && rejected)
    throw new InvalidRepositoryDataError("GitHub returned no usable non-fork repositories");
  return { repositories, rejected };
}

/** @param {readonly Repository[]} repositories @returns {string[]} */
export function listLanguages(repositories) {
  return [...new Set(repositories.map(({ language }) => language))].sort();
}

/** @param {readonly Repository[]} repositories @param {string} language @returns {readonly Repository[]} */
export function filterRepositories(repositories, language) {
  return language === "all"
    ? repositories
    : repositories.filter((repository) => repository.language === language);
}
