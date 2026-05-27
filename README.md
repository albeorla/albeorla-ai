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
| CI / Deploy           | GitHub Actions -> GCS rsync     | Build, sync to bucket, invalidate CDN. Workflow shipped inactive (needs secrets).              |

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
bun run format     # biome format --write .
```

Node >= 20 required. Bun 1.3+ recommended.

## Project layout

```
.
├── public/                 static passthrough (favicon, robots, etc.)
├── src/
│   ├── layouts/            shared <head> / <body> shells
│   ├── pages/              file-based routes
│   ├── lib/                non-component TS helpers
│   ├── styles/             global.css with @theme tokens
│   └── env.d.ts
├── infra/                  Terraform for GCP (bucket, CDN, LB, DNS)
├── .github/workflows/      deploy.yml (inactive until secrets wired)
├── astro.config.mjs
├── biome.json
├── tsconfig.json
└── package.json
```

The design surface (typography scale, color tokens, dark-mode toggle
hook) is scaffolded in `src/styles/global.css` and `src/lib/theme.ts`.
The current `src/pages/index.astro` is intentionally a single centered
heading — the visual design is happening in parallel and will replace
it.

## Deploy

Pushing to `main` triggers `.github/workflows/deploy.yml`, which:

1. Installs deps with Bun.
2. Runs `bun run build` (type-checks, then emits `./dist`).
3. Syncs `./dist/_assets` to `gs://albeorla-ai-site/_assets` with
   `Cache-Control: public, max-age=31536000, immutable`.
4. Syncs the rest of `./dist` with `max-age=60, must-revalidate` so
   HTML updates show up within a minute.
5. Invalidates Cloud CDN at `/*`.

The workflow is committed but inactive until two secrets are added in
GitHub Settings:

- `GCP_WIF_PROVIDER` — full Workload Identity Federation provider
  resource name.
- `GCP_DEPLOY_SA` — email of the deploy service account.

See `infra/README.md` for how to create those.

## Infrastructure

All GCP resources live in [`infra/`](./infra/README.md). Bootstrap and
apply procedure (incl. registrar caveat — the domain is at Name.com on
Vercel DNS, not Google Domains) is documented there. Short version:

```bash
# One-time bootstrap (see infra/README.md for full step list)
gcloud projects create albeorla-ai-site --name="albeorla.ai site"
gcloud beta billing projects link albeorla-ai-site --billing-account=<id>
gcloud storage buckets create gs://albeorla-ai-tfstate \
  --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://albeorla-ai-tfstate --versioning
gcloud auth application-default login

# Apply
cd infra
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Then, at Name.com, replace the nameservers on albeorla.ai with the
# four values from `terraform output name_servers`.
```
