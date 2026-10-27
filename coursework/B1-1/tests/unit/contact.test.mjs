import assert from "node:assert/strict";
import test from "node:test";

import { contactFieldError } from "../../js/domain/contact.js";

test("contact rules execute without browser globals", () => {
  assert.equal("window" in globalThis, false);
  assert.equal("document" in globalThis, false);

  assert.equal(contactFieldError("name", "   "), "required");
  assert.equal(contactFieldError("message", ""), "required");
  assert.equal(contactFieldError("name", " Reviewer "), null);
  assert.equal(contactFieldError("message", "A local note."), null);
});

test("email validation follows native email shape without requiring a dotted domain", () => {
  assert.equal(contactFieldError("email", ""), "required");
  assert.equal(contactFieldError("email", "a@b"), null);
  assert.equal(contactFieldError("email", "reviewer@example.invalid"), null);
  assert.equal(contactFieldError("email", "not-an-email"), "email-format");
  assert.equal(contactFieldError("email", "two@@example.com"), "email-format");
  assert.equal(contactFieldError("email", "has space@example.com"), "email-format");
});

test("unknown contact fields fail instead of silently validating", () => {
  assert.throws(() => contactFieldError("phone", "123"), /Unknown contact field/);
});
