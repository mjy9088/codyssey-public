import assert from "node:assert/strict";
import test from "node:test";

import {
  GitHubHttpError,
  GitHubNetworkError,
  GitHubPayloadError,
  GitHubTimeoutError,
  loadGitHubRepositories,
} from "../../js/data/github.js";

const okResponse = (payload) => ({
  ok: true,
  status: 200,
  json: async () => payload,
});

test("GitHub loading owns HTTP errors and passes normalized results inward", async () => {
  const fetchImpl = async (_url, options) => {
    assert.equal(options.headers.Accept, "application/vnd.github+json");
    assert.ok(options.signal instanceof AbortSignal);
    return okResponse([
      {
        name: "field-notes",
        description: null,
        language: null,
        html_url: "https://github.com/mjy9088/field-notes",
        updated_at: "2026-01-01T00:00:00Z",
        fork: false,
      },
    ]);
  };

  const result = await loadGitHubRepositories({ fetchImpl, timeoutMs: 50 });
  assert.equal(result.repositories[0].language, "Other");

  await assert.rejects(
    loadGitHubRepositories({
      fetchImpl: async () => ({ ok: false, status: 403, json: async () => ({}) }),
      timeoutMs: 50,
    }),
    GitHubHttpError,
  );
});

test("GitHub loading exposes distinct timeout and network errors", async () => {
  const hangingFetch = async (_url, { signal }) =>
    new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), {
        once: true,
      });
    });
  await assert.rejects(
    loadGitHubRepositories({ fetchImpl: hangingFetch, timeoutMs: 5 }),
    GitHubTimeoutError,
  );

  await assert.rejects(
    loadGitHubRepositories({
      fetchImpl: async () => {
        throw new TypeError("offline");
      },
      timeoutMs: 50,
    }),
    GitHubNetworkError,
  );
});

test("a body deadline is a timeout, while malformed JSON is a payload failure", async () => {
  const delayedBody = async (_url, { signal }) =>
    new Response(
      new ReadableStream({
        start(controller) {
          signal.addEventListener(
            "abort",
            () => controller.error(new DOMException("Aborted", "AbortError")),
            { once: true },
          );
        },
      }),
    );
  await assert.rejects(
    loadGitHubRepositories({ fetchImpl: delayedBody, timeoutMs: 5 }),
    GitHubTimeoutError,
  );
  await assert.rejects(
    loadGitHubRepositories({ fetchImpl: async () => new Response("{broken-json"), timeoutMs: 50 }),
    GitHubPayloadError,
  );
});

test("programming errors are not disguised as expected network failures", async () => {
  const failure = new RangeError("broken response decoder");
  class BrokenResponse extends Response {
    json() {
      throw failure;
    }
  }
  await assert.rejects(
    loadGitHubRepositories({ fetchImpl: async () => new BrokenResponse(), timeoutMs: 50 }),
    (error) => error === failure,
  );
});

test("a native response body read failure remains a recoverable network error", async () => {
  const interruptedBody = new Response(
    new ReadableStream({
      start(controller) {
        controller.error(new TypeError("connection reset while reading"));
      },
    }),
  );
  await assert.rejects(
    loadGitHubRepositories({ fetchImpl: async () => interruptedBody, timeoutMs: 50 }),
    GitHubNetworkError,
  );
});
