/** @typedef {"light" | "dark"} Theme */
/** @typedef {{ readonly theme: Theme, readonly explicit: boolean }} ThemeState */

/** @param {unknown} value @returns {Theme | null} */
export function parseThemeChoice(value) {
  return value === "light" || value === "dark" ? value : null;
}

/** @param {Theme | null} choice @param {Theme} systemTheme @returns {ThemeState} */
export function createThemeState(choice, systemTheme) {
  return { theme: choice ?? systemTheme, explicit: choice !== null };
}

/** @param {ThemeState} state @returns {ThemeState} */
export function toggleTheme(state) {
  return { theme: state.theme === "dark" ? "light" : "dark", explicit: true };
}

/** @param {ThemeState} state @param {Theme} systemTheme @returns {ThemeState} */
export function updateSystemTheme(state, systemTheme) {
  return state.explicit ? state : { theme: systemTheme, explicit: false };
}
