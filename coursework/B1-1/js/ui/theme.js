import { createThemeState, toggleTheme, updateSystemTheme } from "../domain/theme.js";
import { requiredElement } from "./elements.js";

/** @typedef {import("../domain/theme.js").Theme} Theme */

/**
 * @param {{
 *   readonly storedChoice: Theme | null,
 *   readonly systemTheme: Theme,
 *   readonly saveChoice: (theme: Theme) => void,
 *   readonly watchSystem: (listener: (theme: Theme) => void) => () => void
 * }} preferences
 * @returns {() => void}
 */
export function initTheme(preferences) {
  const toggle = requiredElement(document, "#theme-toggle", HTMLButtonElement);
  const themeColors = [...document.querySelectorAll('meta[name="theme-color"]')];
  if (!themeColors.length) throw new Error("Required theme-color metadata was not found");

  let state = createThemeState(preferences.storedChoice, preferences.systemTheme);

  /** @param {Theme} theme */
  const applyTheme = (theme) => {
    const dark = theme === "dark";
    document.documentElement.dataset.theme = theme;
    toggle.setAttribute("aria-pressed", String(dark));
    toggle.setAttribute("aria-label", `Switch to ${dark ? "light" : "dark"} theme`);
    const renderedPaper = getComputedStyle(document.documentElement).backgroundColor;
    for (const meta of themeColors) meta.setAttribute("content", renderedPaper);
  };

  const stopSystemWatch = preferences.watchSystem((systemTheme) => {
    const next = updateSystemTheme(state, systemTheme);
    const changed = next.theme !== state.theme;
    state = next;
    if (changed) applyTheme(state.theme);
  });
  const onToggle = () => {
    state = toggleTheme(state);
    applyTheme(state.theme);
    preferences.saveChoice(state.theme);
  };
  toggle.addEventListener("click", onToggle);
  applyTheme(state.theme);
  toggle.hidden = false;
  return () => {
    stopSystemWatch();
    toggle.removeEventListener("click", onToggle);
    toggle.hidden = true;
  };
}
