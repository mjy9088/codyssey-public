import assert from "node:assert/strict";
import test from "node:test";

import {
  filterRepositories,
  InvalidRepositoryDataError,
  listLanguages,
  selectRepositories,
} from "../../js/domain/projects.js";

const repository = (overrides = {}) => ({
  name: "field-notes",
  description: "A small notebook for useful observations.",
  language: "JavaScript",
  html_url: "https://github.com/mjy9088/field-notes",
  updated_at: "2026-02-01T00:00:00Z",
  fork: false,
  ...overrides,
});

test("repository selection executes without browser globals and normalizes public data", () => {
  assert.equal("window" in globalThis, false);
  assert.equal("document" in globalThis, false);

  const result = selectRepositories([
    repository({ name: ` ${"n".repeat(110)} `, description: " ", language: null }),
    repository({ name: "fork", fork: true }),
    repository({ name: "bad-url", html_url: "javascript:void(0)" }),
  ]);

  assert.equal(result.repositories.length, 1);
  assert.equal(result.repositories[0].name.length, 100);
  assert.equal(result.repositories[0].description, null);
  assert.equal(result.repositories[0].language, "Other");
  assert.equal(result.repositories[0].url, `https://github.com/mjy9088/field-notes`);
  assert.equal(result.rejected, 1);
});

test("input and output caps apply before and after fork exclusion", () => {
  const selected = selectRepositories(
    Array.from({ length: 20 }, (_, index) => repository({ name: `candidate-${index}` })),
  );
  assert.equal(selected.repositories.length, 12);
  assert.equal(selected.repositories.at(-1).name, "candidate-11");

  const beyondInputCap = selectRepositories([
    ...Array.from({ length: 100 }, () => repository({ fork: true })),
    repository({ name: "too-late" }),
  ]);
  assert.deepEqual(beyondInputCap, { repositories: [], rejected: 0 });
});

test("invalid-only data is an error rather than a false empty account", () => {
  assert.throws(
    () => selectRepositories([null, repository({ name: " " })]),
    InvalidRepositoryDataError,
  );
  assert.deepEqual(selectRepositories([]), { repositories: [], rejected: 0 });
  assert.deepEqual(selectRepositories([repository({ fork: true })]), {
    repositories: [],
    rejected: 0,
  });
  assert.throws(() => selectRepositories({ unexpected: true }), InvalidRepositoryDataError);
});

test("language listing and filtering operate only on selected candidates", () => {
  const { repositories } = selectRepositories([
    repository({ name: "zeta", language: "TypeScript" }),
    repository({ name: "alpha", language: "JavaScript" }),
    repository({ name: "other", language: null }),
  ]);

  assert.deepEqual(listLanguages(repositories), ["JavaScript", "Other", "TypeScript"]);
  assert.deepEqual(
    filterRepositories(repositories, "JavaScript").map(({ name }) => name),
    ["alpha"],
  );
  assert.equal(filterRepositories(repositories, "all"), repositories);
});

test("normalization rejects unsafe URLs, credentials, ports, and invalid dates", () => {
  const invalid = [
    repository({ html_url: "https://example.invalid/repository" }),
    repository({ html_url: "https://user:password@github.com/repository" }),
    repository({ html_url: "https://github.com:8443/repository" }),
    repository({ updated_at: "not-a-date" }),
    repository({ fork: "false" }),
  ];
  assert.throws(() => selectRepositories(invalid), InvalidRepositoryDataError);
});
