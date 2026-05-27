/**
 * Apply theme before paint to avoid a flash.
 * Order of precedence:
 *   1. ?theme=light|dark URL param (used by design canvas to render iframes)
 *   2. localStorage "theme"
 *   3. prefers-color-scheme (light overrides the dark default)
 * Default (when none of the above apply) is dark — handled by tokens.css.
 */
export const themeInitScript = /* js */ `
(function () {
  try {
    var params = new URLSearchParams(window.location.search);
    var forced = params.get("theme");
    if (forced === "light" || forced === "dark") {
      document.documentElement.setAttribute("data-theme", forced);
      return;
    }
    var stored = localStorage.getItem("theme");
    if (stored === "light" || stored === "dark") {
      document.documentElement.setAttribute("data-theme", stored);
    } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches) {
      document.documentElement.setAttribute("data-theme", "light");
    }
  } catch (e) {}
})();
`;
