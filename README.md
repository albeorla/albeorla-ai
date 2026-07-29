# albeorla.ai

Personal portfolio site for Albert Orlando, served at
[albeorla.ai](https://albeorla.ai). Linked from job applications.

## Stack

| Concern               | Choice                          | Rationale                                                                                      |
| --------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------- |
| Static-site framework | **Astro 6**                     | Content-light, design-forward portfolio. Zero-JS-by-default = top Lighthouse on cheap hosting. |
| Styling               | **Tailwind CSS v4** (Vite plug) | Stable since early 2025. CSS-first `@theme` config; ~100x faster incremental builds.           |
| Type checking         | **TypeScript 6** + `astro check`| Latest stable; Astro 6's first-class TS support.                                               |
| Lint + format         | **Biome 2**                     | One binary, ~25x faster than ESLint+Prettier. Acceptable for a non-React static site.          |
| Package manager       | **Bun 1.3**                     | Fast installs and a single tool. No Node compat gotchas for static SSG.                        |
| Motion                | **Motion 12** + View Transitions| Motion (ex-Framer Motion) for opt-in animations; native View Transitions for route fades.     |
| Content authoring     | Plain `.astro` for now          | MDX is one `bun add @astrojs/mdx` away when the design pass needs prose pages.                 |
| Image optimization    | Astro's built-in `<Image />`    | Framework-native; emits responsive AVIF/WebP at build time.                                    |
| Infra                 | GCP: GCS + Cloud CDN + LB + DNS | Cheap static hosting with anycast, managed SSL, IPv6.                                          |
| CI / Deploy           | GitHub Actions -> GCS rsync     | Build, sync to bucket, invalidate CDN. Live: every push to `main` deploys.                     |

### Considered and rejected

- **Next.js 15 (static export)** — overkill for a content-light site;
  ships React runtime (~80-120 KB) before any portfolio code. Astro
  wins on Lighthouse and hosting cost by a wide margin.
- **shadcn/ui + Radix** — no interactive component needs yet. Will
  reconsider if the design pass demands accessible primitives
  (dialogs, popovers, menus). Easy to add later.
- **MDX from day one** — premature. Static `.astro` first; add MDX
  when a prose page actually exists.
- **ESLint + Prettier** — Biome covers ~100% of what this repo needs
  with one config and one binary.

## Local development

```bash
bun install
bun run dev        # http://localhost:4321
bun run build      # astro check + astro build (static output to ./dist)
bun run preview    # serve ./dist locally
bun run check      # biome lint + format check
bun run lint       # biome lint only
bun run typecheck  # astro check
bun run format     # biome format --write .
```

Node >= 20 required. Bun 1.3+ recommended.

## Project layout

```
.
+-- public/                 static passthrough, copied to the bucket as-is
|   +-- fonts/              self-hosted Geist + Geist Mono variable woff2
|   +-- icons/              inline-able SVGs (social, arrow, sun/moon)
|   +-- .well-known/        security.txt, api-catalog, agent-skills/
|   +-- robots.txt, sitemap*.xml, llms.txt, llms-full.txt, index.md
+-- src/
|   +-- components/         page sections (Hero, Work, Projects, Now,
|   |                       Contact, Footer, ThemeToggle)
|   +-- layouts/            BaseLayout.astro: shared <head> / <body> shell
|   +-- pages/              index.astro, privacy.astro, 404.astro
|   +-- lib/                theme.ts: pre-paint theme init script
|   +-- styles/             tokens.css (design tokens) -> site.css
|   |                       (component CSS) -> global.css (imports both
|   |                       plus Tailwind)
|   +-- env.d.ts
+-- infra/                  Terraform for GCP (bucket, CDN, LB, DNS, WIF)
+-- .github/workflows/      deploy.yml (active; runs on push to main)
+-- astro.config.mjs
+-- biome.json
+-- tsconfig.json
+-- package.json
```

The design system lives in `src/styles/tokens.css` (colors, type scale,
`@font-face`) and `src/styles/site.css` (component classes). Dark mode is
the default; `src/lib/theme.ts` applies the stored or preferred theme
before first paint to avoid a flash, and `ThemeToggle.astro` switches it.
A `?theme=light|dark` URL parameter forces a theme, which the design
canvas uses to render iframes.

The site is a single-page portfolio: `index.astro` composes the section
components in order, with `privacy.astro` and a 404 as the only other
routes. Machine-readable copies of the content (`index.md`, `llms.txt`,
`llms-full.txt`) and the sitemap are checked into `public/` rather than
generated at build time, and the deploy workflow sets their content types
explicitly.

## Deploy

Pushing to `main` triggers `.github/workflows/deploy.yml`, which:

1. Installs deps with Bun.
2. Runs `bun run build` (type-checks, then emits `./dist`).
3. Syncs `./dist/_assets` to `gs://albeorla-ai-site/_assets` with
   `Cache-Control: public, max-age=31536000, immutable`.
4. Syncs the rest of `./dist` with `max-age=60, must-revalidate` so
   HTML updates show up within a minute.
5. Re-uploads the machine-readable files (`robots.txt`, both sitemaps,
   `index.md`, `llms.txt`, `llms-full.txt`, `site.webmanifest`,
   `favicon.ico`, and everything under `.well-known/`) with explicit
   content types, since `rsync` guesses them wrong.
6. Invalidates Cloud CDN at `/*`.

The workflow is active. It authenticates with Workload Identity
Federation using two repo secrets, both already set:

- `GCP_WIF_PROVIDER` - full Workload Identity Federation provider
  resource name.
- `GCP_DEPLOY_SA` - email of the deploy service account.

See `infra/README.md` for how those were created and how to rotate them.

## Infrastructure

All GCP resources live in [`infra/`](./infra/README.md), in project
`albeorla-ai-site`. The stack is applied and serving: the domain resolves
to the load balancer, the managed SSL certificate is `ACTIVE`, and the
nameservers have been cut over from Vercel to Google Cloud DNS. The
one-time bootstrap and the registrar history are documented in
`infra/README.md`; you should not need to repeat either.

Day-to-day changes:

```bash
cd infra
terraform init      # first time on a new machine
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform needs application-default credentials
(`gcloud auth application-default login`) and reads state from
`gs://albeorla-ai-tfstate`. `infra/terraform.tfvars` is gitignored; copy
`terraform.tfvars.example` if you are setting up a fresh checkout.
