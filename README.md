# Website Builder Migrate Skill

Migrate a site built on a website builder (Webflow, Framer, Squarespace, Wix, Carrd, etc.) to a self-hosted static site. Uses `wget` to mirror the published site, then cleans up assets, URLs, and platform-specific artifacts so it's ready to deploy anywhere.

## Installation

### Via skills.sh (recommended)

```bash
npx skills add stevysmith/website-builder-migrate-skill
```

### Via Claude Code plugin commands

```
/plugin marketplace add stevysmith/website-builder-migrate-skill
/plugin install website-builder-migrate@website-builder-migrate-skill
```

After installation, the `/website-builder-migrate` skill is available in Claude Code.

## Usage

```
/website-builder-migrate https://www.example.com/
```

Pass the URL of a live, publicly accessible builder-hosted site. The skill will:

1. **Mirror** the full site including CDN-hosted assets (images, CSS, JS)
2. **Consolidate** into a clean `site/` directory structure
3. **Rewrite** all asset URLs to local paths
4. **Fix** common builder-export issues (SRI integrity blocks, missing webpack chunks, mangled inline styles, double-encoded URLs, broken forms)
5. **Verify** all asset references resolve correctly
6. **Deploy** to Render, Netlify, Vercel, or any static host

## Supported Platforms

The Phase 1–7 workflow is platform-agnostic, with a per-platform notes table for CDN domains, chunk patterns, and common gotchas:

| Platform | Notes |
|---|---|
| **Webflow** | Battle-tested. Multiple CDN site IDs, `webflow.achunk.*` webpack chunks, heavy SRI tags. |
| **Framer** | React SPA with dynamic route bundles. Verify hydration in the browser. |
| **Squarespace** | Heavy template JS, server-side image transforms. |
| **Wix** | Hardest case — extremely SPA-driven; works only for static template sites. |
| **Carrd** | Trivial — single inlined HTML; full workflow is overkill. |

For unfamiliar platforms, the skill includes a diagnostic checklist (CDN domain / SRI tags / chunk map) to drive the workflow.

## What It Handles

- Multiple CDN site IDs (site assets vs CMS content)
- Inline `background-image:url()` assets that `wget` misses
- Mangled URLs from `wget --convert-links` in inline styles
- Double-encoded CMS filenames (`%2520`, `%252B`, `%2526`)
- Subdirectory page structures (blog posts, career pages, etc.)
- **SRI `integrity` attribute blocks** — the most common cause of a blank-rendered migration; `--convert-links` modifies CSS bytes so the SHA-384 hash no longer matches
- **Dynamically-loaded webpack chunks** — `webflow.achunk.*` and equivalents that `wget` doesn't catch
- **CSS-internal `url(../font.ttf)` paths** that break when assets are reorganized
- Platform metadata attribute cleanup (`data-wf-*`, `data-framer-*`, generator meta tags)
- In-browser verification step (catches what static asset checks miss)

## Output Structure

```
site/
  index.html
  about.html
  blog.html
  post/                # blog posts
  careers/             # career pages
  assets/
    css/               # stylesheets
    js/                # builder runtime + chunks
    images/            # all media (images, SVGs, videos)
```

## Prerequisites

- `wget` must be installed (comes with macOS/Linux)
- The site must be published and publicly accessible
- Optional: `agent-browser` skill for visual verification

## Deploy

| Platform | Command |
|----------|---------|
| Stacktree | `(cd site && zip -qr ../site.zip .) && curl -F "file=@site.zip" https://api.stacktr.ee/sites` — no account; returns a private preview URL |
| Render | Publish path: `./site` |
| Netlify | `npx netlify-cli deploy --dir=./site --prod` |
| Vercel | `npx vercel ./site --prod` |

Tip: deploy to Stacktree first to verify the migration on a private, unguessable URL before pointing DNS anywhere — anonymous uploads need no signup and last 24 hours.

## Limitations

- **JavaScript interactions** — the builder's runtime continues to work but is monolithic (Webflow ~500KB; Framer per-route bundles)
- **CMS content** — captured as static HTML at time of mirroring; won't update dynamically
- **Forms** — builder forms won't work without their backend; use Formspree, Netlify Forms, Basin, etc.
- **Site search** — native search won't work; use Algolia, Pagefind, or similar
- **Wix and other heavily-SPA builders** — wget mirroring may produce incomplete output for client-rendered content

## Learn More

- [skills.sh](https://skills.sh) — Discover more Claude Code skills
