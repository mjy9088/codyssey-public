import { ProjectLoadError } from "../domain/project-load.js";
import { InvalidRepositoryDataError, selectRepositories } from "../domain/projects.js";

const API_URL = "https://api.github.com/users/mjy9088/repos?per_page=100&sort=updated";
export const GITHUB_REQUEST_TIMEOUT_MS = 8000;

/** @typedef {(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>} FetchImplementation */

export class GitHubHttpError extends ProjectLoadError {
  /** @param {number} status */
  constructor(status) {
    super("http", `GitHub returned ${status}`);
    this.name = "GitHubHttpError";
    this.status = status;
  }
}

export class GitHubTimeoutError extends ProjectLoadError {
  constructor() {
    super("timeout", "GitHub took too long to respond");
    this.name = "GitHubTimeoutError";
  }
}

export class GitHubNetworkError extends ProjectLoadError {
  /** @param {unknown} cause */
  constructor(cause) {
    super("network", "GitHub could not be reached", { cause });
    this.name = "GitHubNetworkError";
  }
}

export class GitHubPayloadError extends ProjectLoadError {
  /** @param {unknown} cause */
  constructor(cause) {
    super("payload", "GitHub returned unusable repository data", { cause });
    this.name = "GitHubPayloadError";
  }
}

/**
 * Load and normalize the portfolio repository candidates.
 *
 * @param {{ fetchImpl?: FetchImplementation, timeoutMs?: number }} [options]
 * @returns {Promise<import("../domain/projects.js").RepositorySelection>}
 */
export async function loadGitHubRepositories(options = {}) {
  const fetchImpl = options.fetchImpl ?? fetch;
  const timeoutMs = options.timeoutMs ?? GITHUB_REQUEST_TIMEOUT_MS;
  const controller = new AbortController();
  let deadlineReached = false;
  const timeout = setTimeout(() => {
    deadlineReached = true;
    controller.abort();
  }, timeoutMs);

  try {
    let response;
    try {
      response = await fetchImpl(API_URL, {
        headers: { Accept: "application/vnd.github+json" },
        signal: controller.signal,
      });
    } catch (error) {
      if (deadlineReached) throw new GitHubTimeoutError();
      if (error instanceof TypeError) throw new GitHubNetworkError(error);
      throw error;
    }
    if (!response.ok) throw new GitHubHttpError(response.status);

    /** @type {unknown} */
    let payload;
    try {
      payload = await response.json();
    } catch (error) {
      if (deadlineReached) throw new GitHubTimeoutError();
      if (error instanceof SyntaxError) throw new GitHubPayloadError(error);
      if (error instanceof TypeError) throw new GitHubNetworkError(error);
      throw error;
    }
    try {
      return selectRepositories(payload);
    } catch (error) {
      if (error instanceof InvalidRepositoryDataError) throw new GitHubPayloadError(error);
      throw error;
    }
  } finally {
    clearTimeout(timeout);
  }
}
