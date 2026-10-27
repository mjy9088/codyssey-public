import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";
import {
  GitHubHttpError,
  GitHubNetworkError,
  GitHubPayloadError,
  GitHubTimeoutError,
  loadGitHubRepositories,
} from "../../js/data/github.js";

test("the native request fixes its endpoint, header and abort ownership", async (t) => {
  let signal;
  t.mock.method(globalThis, "fetch", async (url, options) => {
    assert.equal(url, "https://api.github.com/users/mjy9088/repos?per_page=100&sort=updated");
    assert.equal(options.headers.Accept, "application/vnd.github+json");
    signal = options.signal;
    return new Response("[]");
  });
  assert.deepEqual(await loadGitHubRepositories(), { repositories: [], rejected: 0 });
  assert.equal(signal.aborted, true);
});

test("documented native fetch rejection is a network failure with its original cause", async (t) => {
  const failure = new TypeError("native fetch connection failure");
  t.mock.method(globalThis, "fetch", async () => {
    throw failure;
  });
  await assert.rejects(
    loadGitHubRepositories(),
    (error) => error instanceof GitHubNetworkError && error.cause === failure,
  );
});

test("a semantic request implementation's constructor error retains its identity", async () => {
  let failure;
  await assert.rejects(
    loadGitHubRepositories({
      requestJson: async () => {
        try {
          return new Response("invalid 204 body", { status: 204 });
        } catch (error) {
          failure = error;
          throw error;
        }
      },
    }),
    (error) => error === failure && error instanceof TypeError,
  );
});

for (const state of ["consumed", "locked"]) {
  test(`a ${state} native response preserves its body-state error`, async (t) => {
    const response = new Response("{}");
    if (state === "consumed") await response.text();
    const reader = state === "locked" ? response.body.getReader() : null;
    t.after(async () => {
      reader?.releaseLock();
      if (!response.bodyUsed) await response.body?.cancel();
    });
    const read = response.json.bind(response);
    let failure;
    response.json = async () => {
      try {
        return await read();
      } catch (error) {
        failure = error;
        throw error;
      }
    };
    await assert.rejects(
      loadGitHubRepositories({ requestJson: () => response.json() }),
      (error) => error === failure && error instanceof TypeError,
    );
  });
}

test("a native unread response's interrupted stream is a recoverable network failure", async (t) => {
  const failure = new TypeError("connection reset while reading");
  const response = new Response(
    new ReadableStream({
      start(controller) {
        controller.error(failure);
      },
    }),
  );
  t.mock.method(globalThis, "fetch", async () => response);
  await assert.rejects(
    loadGitHubRepositories(),
    (error) => error instanceof GitHubNetworkError && error.cause === failure,
  );
});

test("malformed JSON is a payload failure rather than a network failure", async (t) => {
  t.mock.method(globalThis, "fetch", async () => new Response("{broken-json"));
  await assert.rejects(
    loadGitHubRepositories(),
    (error) => error instanceof GitHubPayloadError && error.cause instanceof SyntaxError,
  );
});

test("request and body deadlines remain distinct from programming errors", async (t) => {
  const hangingRequest = (signal) =>
    new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason), { once: true });
    });
  await assert.rejects(
    loadGitHubRepositories({ requestJson: hangingRequest, timeoutMs: 5 }),
    GitHubTimeoutError,
  );
  const delayedBody = async (_url, { signal }) =>
    new Response(
      new ReadableStream({
        start(controller) {
          signal.addEventListener("abort", () => controller.error(signal.reason), { once: true });
        },
      }),
    );
  t.mock.method(globalThis, "fetch", delayedBody);
  await assert.rejects(loadGitHubRepositories({ timeoutMs: 5 }), GitHubTimeoutError);
  const failure = new RangeError("unexpected request implementation bug");
  await assert.rejects(
    loadGitHubRepositories({
      requestJson: async () => {
        throw failure;
      },
    }),
    (error) => error === failure,
  );
});

test("a non-OK response releases its request before HTTP failure reaches the caller", async (t) => {
  let signal;
  t.mock.method(globalThis, "fetch", async (_url, options) => {
    signal = options.signal;
    return new Response("unread error body", { status: 403 });
  });
  await assert.rejects(loadGitHubRepositories(), GitHubHttpError);
  assert.equal(signal.aborted, true);
});

test("a native streaming HTTP error actually closes its response connection", async (t) => {
  let closed;
  const connectionClosed = new Promise((resolve) => {
    closed = resolve;
  });
  const server = createServer((_request, response) => {
    response.on("close", closed);
    response.writeHead(403, { "Content-Type": "application/json" });
    response.write("unfinished error body");
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const nativeFetch = globalThis.fetch;
  t.mock.method(globalThis, "fetch", (_url, options) =>
    nativeFetch(`http://127.0.0.1:${address.port}`, options),
  );
  let deadline;
  try {
    await assert.rejects(loadGitHubRepositories(), GitHubHttpError);
    await Promise.race([
      connectionClosed,
      new Promise((_resolve, reject) => {
        deadline = setTimeout(() => reject(new Error("HTTP body stayed open")), 2000);
      }),
    ]);
  } finally {
    clearTimeout(deadline);
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
