---
title: Docs Site
description: How the tnix.dev documentation site is built with Ox Content and deployed to Cloudflare Pages.
---

# Docs Site

The documentation at [tnix.dev](https://tnix.dev) is generated from the
Markdown files in `docs/` by [Ox Content](https://github.com/ubugeeei/ox-content)
running as a Vite plugin, and is served by Cloudflare Pages.

## Layout

| Path | Contents |
| --- | --- |
| `docs/*.md`, `docs/tutorial/`, `docs/reference/` | pages; the URL is the file path without `.md` |
| `docs/public/` | copied verbatim to the site root: brand assets, `og-image.png`, `install.sh`, `_headers`, `_redirects` |
| `docs/.vite/brand.ts` | palette, fonts, code theme and CSS layered on the Ox Content theme (see [Brand](./brand.md)) |
| `docs/.vite/tnix-grammar.ts` | the TextMate grammar used to highlight `tnix` code fences |
| `vite.docs.config.ts` | site configuration: navigation, theme, highlighting, search, OG metadata |
| `wrangler.toml` | Cloudflare Pages project settings |

Navigation is explicit: add a new page to the `navigation` array in
`vite.docs.config.ts`, under one of the Start, Tutorial, Guides, Reference or
Project groups.

## Writing pages

- Start each page with front matter containing `title` and `description`; the
  description becomes the page's meta and OG description.
- Link to other pages with relative `.md` links (`[CLI](./reference/cli.md)`).
  Ox Content rewrites them to site URLs, and the link checker can verify them.
  Link to repository files with full GitHub URLs, since they are not part of
  the site.
- Use `tnix` as the fence language for `.tnix` and `.d.tnix` code, and add a
  file name in brackets to give a block a title: ```` ```tnix [hello.tnix] ````.
  `{2,4-5}` after the language highlights lines.
- GitHub-style alerts (`> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`,
  `> [!IMPORTANT]`) render as callouts.
- Diagrams are inline SVG inside `<figure class="tx-diagram">`, using the
  `d-box`, `d-accent`, `d-amber`, `d-mint`, `d-line` and `d-text` classes so
  they follow the light and dark themes.
- Code shown as tool output should be real output. When documenting syntax that
  is not implemented yet, mark it as upcoming.

## Build locally

```bash
nix develop --accept-flake-config
pnpm install --frozen-lockfile
vp run docs:build
```

The site is written to `dist/docs`. Preview it with any static server, for
example `pnpm dlx serve dist/docs`. Search (`search-index.json`) is generated at
build time.

## Deploy

tnix.dev is a Cloudflare Pages project named `tnix`, configured by
`wrangler.toml` at the repository root. Deployment is a direct upload with
Wrangler, the Cloudflare CLI:

```bash
vp run docs:deploy
```

This builds the site and runs
`wrangler pages deploy dist/docs --project-name tnix`. Wrangler needs to be
authenticated, either interactively with `wrangler login` or with the
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` environment variables. The
token needs the **Cloudflare Pages: Edit** permission. Deploys from the `main`
branch become the production deployment; any other branch name (pass
`--branch <name>`) creates a preview deployment.

The Docs workflow in `.github/workflows/docs.yml` can perform the same deploy
from CI. It builds the site on every run, and when the repository has the
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets, it deploys pushes to
`main` to production and same-repository pull requests to preview URLs. Without
the secrets the deploy step is skipped.

### Headers and redirects

Cloudflare Pages reads two files from the site root:

- [`docs/public/_headers`](https://github.com/ubugeeei-prod/tnix/blob/main/docs/public/_headers)
  sets security headers for every response, serves `/install.sh` as
  `text/plain`, and gives fingerprinted assets a long cache lifetime.
- [`docs/public/_redirects`](https://github.com/ubugeeei-prod/tnix/blob/main/docs/public/_redirects)
  defines short links:

| Path | Destination |
| --- | --- |
| `/gh` | the GitHub repository |
| `/install` | `/install.sh` |
| `/latest` | the latest GitHub release |
| `/download/*` | `https://github.com/ubugeeei-prod/tnix/releases/download/:splat` |
| `/discussions`, `/issues` | the repository's discussions and issues |

The installer script downloads release archives through `/download/...`, so
release asset URLs stay stable even if hosting changes.

### Social previews

Every page advertises `https://tnix.dev/og-image.png` (rendered from
`docs/public/brand/og-image.svg`) as its Open Graph image. Re-render it after
editing the SVG:

```bash
rsvg-convert -w 1200 -h 630 docs/public/brand/og-image.svg -o docs/public/og-image.png
```

Set `TNIX_DOCS_SITE_URL` when building for a different origin, such as a
staging domain, so absolute URLs in the metadata point there.
