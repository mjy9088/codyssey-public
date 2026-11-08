import assert from "node:assert/strict";
import test from "node:test";
import {
  createThemeState,
  parseThemeChoice,
  toggleTheme,
  updateSystemTheme,
} from "../../js/domain/theme.js";

test("theme choices accept only the persisted light/dark values", () => {
  assert.equal(typeof window, "undefined");
  assert.equal(typeof document, "undefined");
  assert.equal(parseThemeChoice("light"), "light");
  assert.equal(parseThemeChoice("dark"), "dark");
  for (const invalid of [null, undefined, "", "DARK", " dark ", 0, true, {}]) {
    assert.equal(parseThemeChoice(invalid), null);
  }
});

for (const systemTheme of ["light", "dark"]) {
  test(`initial selection follows ${systemTheme} only without an explicit preference`, () => {
    assert.deepEqual(createThemeState(null, systemTheme), {
      theme: systemTheme,
      explicit: false,
    });
    for (const choice of ["light", "dark"]) {
      assert.deepEqual(createThemeState(choice, systemTheme), { theme: choice, explicit: true });
    }
  });
}

test("system preference changes update an automatic theme without mutating its prior state", () => {
  const initial = Object.freeze(createThemeState(null, "light"));
  const next = updateSystemTheme(initial, "dark");
  assert.deepEqual(next, { theme: "dark", explicit: false });
  assert.deepEqual(initial, { theme: "light", explicit: false });
  assert.deepEqual(updateSystemTheme(next, "light"), { theme: "light", explicit: false });
});

test("a toggle makes the in-memory choice explicit and later system changes cannot replace it", () => {
  const automatic = Object.freeze(createThemeState(null, "light"));
  const selected = Object.freeze(toggleTheme(automatic));
  assert.deepEqual(selected, { theme: "dark", explicit: true });
  assert.deepEqual(automatic, { theme: "light", explicit: false });
  assert.deepEqual(updateSystemTheme(selected, "light"), { theme: "dark", explicit: true });
  const toggledAgain = toggleTheme(selected);
  assert.deepEqual(toggledAgain, { theme: "light", explicit: true });
  assert.deepEqual(updateSystemTheme(toggledAgain, "dark"), { theme: "light", explicit: true });
});

test("a restored explicit choice keeps precedence before the visitor clicks anything", () => {
  const restored = Object.freeze(createThemeState("light", "dark"));
  assert.deepEqual(updateSystemTheme(restored, "dark"), { theme: "light", explicit: true });
  assert.deepEqual(toggleTheme(restored), { theme: "dark", explicit: true });
});
