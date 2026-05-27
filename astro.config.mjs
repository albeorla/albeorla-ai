// @ts-check

import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

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
  },
  experimental: {
    // View Transitions are stable in Astro 5; nothing experimental needed.
  },
});
