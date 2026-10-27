import { requiredElement } from "./elements.js";

const STORAGE_KEY = "portfolio-theme";
const DARK = "dark";
const LIGHT = "light";

/** @typedef {"dark" | "light"} Theme */

/** @returns {Theme | null} */
function readStoredTheme() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored === DARK || stored === LIGHT ? stored : null;
  } catch {
    return null;
  }
}

/** @param {Theme} theme */
function writeStoredTheme(theme) {
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // The in-memory explicit choice still owns this page when storage is unavailable.
  }
}

export function initTheme() {
  const toggle = requiredElement(document, "#theme-toggle", HTMLButtonElement);
  const themeColors = [...document.querySelectorAll('meta[name="theme-color"]')];
  if (!themeColors.length) throw new Error("Required theme-color metadata was not found");

  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
  let selectedTheme = readStoredTheme();

  /** @param {Theme} theme */
  const applyTheme = (theme) => {
    const dark = theme === DARK;
    document.documentElement.dataset.theme = theme;
    toggle.setAttribute("aria-pressed", String(dark));
    toggle.setAttribute("aria-label", `Switch to ${dark ? LIGHT : DARK} theme`);
    const renderedPaper = getComputedStyle(document.documentElement).backgroundColor;
    for (const meta of themeColors) meta.setAttribute("content", renderedPaper);
  };

  applyTheme(selectedTheme ?? (systemTheme.matches ? DARK : LIGHT));
  systemTheme.addEventListener("change", (event) => {
    if (selectedTheme === null) applyTheme(event.matches ? DARK : LIGHT);
  });
  toggle.addEventListener("click", () => {
    selectedTheme = document.documentElement.dataset.theme === DARK ? LIGHT : DARK;
    applyTheme(selectedTheme);
    writeStoredTheme(selectedTheme);
  });
}
