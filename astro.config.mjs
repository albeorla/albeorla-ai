// astro.config.mjs — runs in Node. @ts-check is intentionally omitted so we
// can use `node:` builtins without pulling in @types/node.

import { execSync } from "node:child_process";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

// Build-time constants — injected into the bundle as string literals.
let commitSha = "dev";
try {
  commitSha = execSync("git rev-parse --short HEAD", { encoding: "utf8" }).trim();
} catch {
  // Not in a git tree; leave as "dev".
}
const buildDate = new Date().toISOString().slice(0, 10);

// https://astro.build/config
export default defineConfig({
  site: "https://albeorla.ai",
  output: "static",
  trailingSlash: "ignore",
  build: {
    format: "directory",
    assets: "_assets",
    inlineStylesheets: "auto",
  },
  vite: {
    plugins: [tailwindcss()],
    define: {
      __BUILD_COMMIT__: JSON.stringify(commitSha),
      __BUILD_DATE__: JSON.stringify(buildDate),
    },
  },
  experimental: {
    // View Transitions are stable in Astro 5; nothing experimental needed.
  },
});
