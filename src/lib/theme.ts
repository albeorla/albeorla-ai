/**
 * Dark mode scaffolding. Inline this script in <head> to avoid FOUC.
 * The real design work will likely add a toggle UI on top of this.
 */
export const themeInitScript = /* js */ `
(function () {
  try {
    var stored = localStorage.getItem("theme");
    var prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    var theme = stored || (prefersDark ? "dark" : "light");
    document.documentElement.classList.toggle("dark", theme === "dark");
    document.documentElement.dataset.theme = theme;
  } catch (_) {}
})();
`;
