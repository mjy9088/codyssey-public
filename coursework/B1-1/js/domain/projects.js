const MAX_REPOSITORY_INPUTS = 100;
const MAX_SELECTED_PROJECTS = 12;

const DEFAULT_LANGUAGE = "Other";

/**
 * @typedef {{
 *   readonly name: string,
 *   readonly url: string,
 *   readonly description: string | null,
 *   readonly language: string | null,
 *   readonly updatedAt: number,
 *   readonly fork: boolean
 * }} RepositoryCandidate
 * @typedef {Omit<RepositoryCandidate, "language"> & { readonly language: string }} Repository
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

/** @param {RepositoryCandidate} value @returns {Repository | null} */
function normalizeRepository(value) {
  const { name, url, description, language, updatedAt, fork } = value;
  if (!name.trim() || Number.isNaN(new Date(updatedAt).getTime())) return null;

  let parsedUrl;
  try {
    parsedUrl = new URL(url);
  } catch {
    return null;
  }
  if (parsedUrl.origin !== "https://github.com" || parsedUrl.username || parsedUrl.password)
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

/** @param {Iterable<RepositoryCandidate | null>} candidates @returns {RepositorySelection} */
export function selectRepositories(candidates) {
  /** @type {Repository[]} */
  const accepted = [];
  let rejected = 0;
  let inspected = 0;
  for (const candidate of candidates) {
    const repository = candidate === null ? null : normalizeRepository(candidate);
    if (repository === null) rejected += 1;
    else if (!repository.fork) accepted.push(repository);
    inspected += 1;
    if (inspected === MAX_REPOSITORY_INPUTS) break;
  }
  const repositories = accepted
    .sort((left, right) => right.updatedAt - left.updatedAt)
    .slice(0, MAX_SELECTED_PROJECTS);
  if (!repositories.length && rejected)
    throw new InvalidRepositoryDataError("No usable non-fork repositories were supplied");
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
