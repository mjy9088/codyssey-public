import assert from "node:assert/strict";
import test from "node:test";
import { GitHubPayloadError, loadGitHubRepositories } from "../../js/data/github.js";

const record = (overrides = {}) => ({
  name: "field-notes",
  html_url: "https://github.com/mjy9088/field-notes",
  description: null,
  language: null,
  updated_at: "2026-02-01T00:00:00Z",
  fork: false,
  ...overrides,
});

test("the GitHub adapter decodes wire names and timestamps before supplying domain values", async () => {
  const result = await loadGitHubRepositories({ requestJson: async () => [record()] });
  assert.deepEqual(result, {
    repositories: [
      {
        name: "field-notes",
        url: "https://github.com/mjy9088/field-notes",
        description: null,
        language: "Other",
        updatedAt: Date.UTC(2026, 1, 1),
        fork: false,
      },
    ],
    rejected: 0,
  });
});

test("malformed GitHub field types and timestamps are counted without reaching the typed domain", async () => {
  const malformed = [
    null,
    [],
    {},
    record({ name: 3 }),
    record({ html_url: null }),
    record({ description: false }),
    record({ language: 1 }),
    record({ updated_at: "not-a-date" }),
    record({ fork: "false" }),
  ];
  const result = await loadGitHubRepositories({
    requestJson: async () => [...malformed, record()],
  });
  assert.equal(result.rejected, malformed.length);
  assert.equal(result.repositories.length, 1);
});

test("invalid response containers remain payload failures at the GitHub boundary", async () => {
  await assert.rejects(
    loadGitHubRepositories({ requestJson: async () => ({ unexpected: true }) }),
    GitHubPayloadError,
  );
});

test("the input budget stops wire decoding before a record beyond the first hundred", async () => {
  let decoded = false;
  const beyondBudget = {
    ...record(),
    get updated_at() {
      decoded = true;
      throw new Error("Record beyond the domain intake budget was decoded");
    },
  };
  const result = await loadGitHubRepositories({
    requestJson: async () => [
      ...Array.from({ length: 100 }, () => record({ fork: true })),
      beyondBudget,
    ],
  });
  assert.deepEqual(result, { repositories: [], rejected: 0 });
  assert.equal(decoded, false);
});
