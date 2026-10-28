import { parseThemeChoice } from "../domain/theme.js";

/** @typedef {import("../domain/theme.js").Theme} Theme */
const STORAGE_KEY = "portfolio-theme";

/** @param {unknown} error */
function isStorageFailure(error) {
  return (
    error instanceof DOMException &&
    (error.name === "SecurityError" || error.name === "QuotaExceededError")
  );
}

/** @returns {Theme | null} */
function readChoice() {
  try {
    return parseThemeChoice(localStorage.getItem(STORAGE_KEY));
  } catch (error) {
    if (isStorageFailure(error)) return null;
    throw error;
  }
}

/** @param {Theme} theme */
function saveChoice(theme) {
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch (error) {
    if (!isStorageFailure(error)) throw error;
  }
}

export function createThemePreferences() {
  const media = matchMedia("(prefers-color-scheme: dark)");
  /** @type {Theme} */
  const systemTheme = media.matches ? "dark" : "light";
  return {
    storedChoice: readChoice(),
    systemTheme,
    saveChoice,
    /** @param {(theme: Theme) => void} listener */
    watchSystem(listener) {
      /** @param {MediaQueryListEvent} event */
      const onChange = (event) => listener(event.matches ? "dark" : "light");
      media.addEventListener("change", onChange);
      return () => media.removeEventListener("change", onChange);
    },
  };
}
