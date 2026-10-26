const STORAGE_KEY = "portfolio-theme";
const DARK = "dark";
const LIGHT = "light";

const readStoredTheme = () => {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored === DARK || stored === LIGHT ? stored : null;
  } catch {
    return null;
  }
};

const writeStoredTheme = (theme) => {
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // The explicit choice still applies to this page when storage is unavailable.
  }
};

export const initTheme = () => {
  const toggle = document.querySelector("#theme-toggle");
  const themeColors = document.querySelectorAll('meta[name="theme-color"]');
  if (!(toggle instanceof HTMLButtonElement)) return;
  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
  let selectedTheme = readStoredTheme();

  const applyTheme = (theme) => {
    const dark = theme === DARK;
    document.documentElement.dataset.theme = theme;
    toggle.setAttribute("aria-pressed", String(dark));
    toggle.setAttribute("aria-label", `Switch to ${dark ? LIGHT : DARK} theme`);
    themeColors.forEach((meta) => meta.setAttribute("content", dark ? "#151816" : "#f4f1e8"));
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
};
