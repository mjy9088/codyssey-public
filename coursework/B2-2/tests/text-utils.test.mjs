import assert from "node:assert/strict";
import { test } from "node:test";
import { compactWhitespace, initials, slug } from "../src/text-utils.mjs";

test("ASCII slugs normalize accents and punctuation", () => {
  assert.equal(slug("  Café / tools!  "), "cafe-tools");
  assert.equal(slug("---"), "");
});
test("whitespace compaction preserves words", () => {
  assert.equal(compactWhitespace("  one\n\t two  "), "one two");
  assert.equal(compactWhitespace(" \n "), "");
});
test("initials handle Unicode code points and empty names", () => {
  assert.equal(initials("  Ada  Lovelace "), "AL");
  assert.equal(initials(""), "");
  assert.equal(initials("Émile Zola"), "ÉZ");
});
