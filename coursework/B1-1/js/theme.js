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
  }
};

const preferredTheme = () => readStoredTheme() ?? (matchMedia("(prefers-color-scheme: dark)").matches ? DARK : LIGHT);

export const initTheme = () => {
  const toggle = document.querySelector("#theme-toggle");
  const themeColor = document.querySelector('meta[name="theme-color"]');
  if (!(toggle instanceof HTMLButtonElement)) return;

  const applyTheme = (theme) => {
    const dark = theme === DARK;
    document.documentElement.dataset.theme = theme;
    toggle.setAttribute("aria-pressed", String(dark));
    toggle.setAttribute("aria-label", `Switch to ${dark ? LIGHT : DARK} theme`);
    themeColor?.setAttribute("content", dark ? "#151816" : "#f4f1e8");
  };

  applyTheme(preferredTheme());
  toggle.addEventListener("click", () => {
    const next = document.documentElement.dataset.theme === DARK ? LIGHT : DARK;
    applyTheme(next);
    writeStoredTheme(next);
  });
};
