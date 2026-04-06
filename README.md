# Webflow Migrate Skill

Migrate your own Webflow-hosted site to a self-hosted static site. Uses `wget` to mirror the published site, then cleans up assets, URLs, and Webflow artifacts so it's ready to deploy anywhere.

## Installation

### Via skills.sh (recommended)

```bash
npx skills add stevysmith/webflow-migrate-skill
```

### Via Claude Code plugin commands

```
/plugin marketplace add stevysmith/webflow-migrate-skill
/plugin install webflow-migrate@webflow-migrate-skill
```

After installation, the `/webflow-migrate` skill is available in Claude Code.

## Usage

```
/webflow-migrate https://www.example.com/
```

Pass the URL of a live, publicly accessible Webflow site. The skill will:

1. **Mirror** the full site including CDN-hosted assets (images, CSS, JS)
2. **Consolidate** into a clean `site/` directory structure
3. **Rewrite** all asset URLs to local paths
4. **Fix** common Webflow export issues (mangled inline styles, double-encoded URLs, broken forms, outdated copy)
5. **Verify** all asset references resolve correctly
6. **Deploy** to Render, Netlify, Vercel, or any static host

## What It Handles

- Multiple CDN site IDs (site assets vs CMS content)
- Inline `background-image:url()` assets that `wget` misses
- Mangled URLs from `wget --convert-links` in inline styles
- Double-encoded Webflow CMS filenames (`%2520`, `%252B`, `%2526`)
- Subdirectory page structures (blog posts, career pages, etc.)
- Webflow data attributes and HTML comments cleanup
- Copyright year updates
- Form identification (Webflow forms won't work without their backend)

## Output Structure

```
site/
  index.html
  about.html
  blog.html
  post/               # blog posts
  careers/             # career pages
  assets/
    css/               # stylesheets
    js/                # Webflow runtime + chunks
    images/            # all media (images, SVGs, videos)
```

## Prerequisites

- `wget` must be installed (comes with macOS/Linux)
- The site must be published and publicly accessible
- Optional: Playwright MCP for visual verification

## Deploy

| Platform | Command |
|----------|---------|
| Render | Publish path: `./site` |
| Netlify | `npx netlify-cli deploy --dir=./site --prod` |
| Vercel | `npx vercel ./site --prod` |

## Limitations

- **JavaScript interactions** - Webflow's JS runtime continues to work but is a monolithic ~500KB file
- **CMS content** - Captured as static HTML at time of mirroring; won't update dynamically
- **Forms** - Webflow forms won't work without their backend; use Formspree, Netlify Forms, etc.
- **Site search** - Webflow's native search won't work; use Algolia, Pagefind, or similar

## Learn More

- [skills.sh](https://skills.sh) - Discover more Claude Code skills
