---
name: webflow-migrate
description: Migrate your own Webflow-hosted site to a self-hosted static site. Use when the user wants to migrate, move, or self-host their own Webflow site on Render, Netlify, Vercel, or another hosting provider.
---

# Webflow Site Migration

Migrate your own Webflow-hosted site to a self-hostable static site. Uses `wget` to mirror the published site, then cleans up assets, URLs, and Webflow artifacts.

## When to Use

- User wants to migrate off Webflow without paying for code export
- User wants to self-host a Webflow site on Render, Netlify, Vercel, etc.
- User wants a local copy of a Webflow site they can edit and maintain

## Prerequisites

- The site must be **published and publicly accessible** (wget mirrors the live site)
- `wget` must be installed (comes with macOS/Linux)
- Optionally: `agent-browser` skill for visual verification

## Migration Workflow

Follow these phases in order. Each phase has specific steps — do not skip phases.

### Phase 1: Mirror the Live Site

Use `wget` with CDN spanning to download the full site including assets hosted on Webflow's CDN.

```bash
wget --mirror \
  --convert-links \
  --adjust-extension \
  --page-requisites \
  --span-hosts \
  --domains=<DOMAIN>,cdn.prod.website-files.com \
  --no-parent \
  https://<DOMAIN>/
```

**Key flags:**
- `--span-hosts --domains=...,cdn.prod.website-files.com` — required because Webflow serves assets from a separate CDN domain
- `--convert-links` — rewrites absolute URLs to relative paths
- `--page-requisites` — downloads CSS, JS, images, fonts referenced by each page
- `--adjust-extension` — adds `.html` extensions for clean URLs

**Common issues:**
- Videos with URL-encoded paths (`%2F`, `%20`) may not download automatically. Check for these and download manually with `wget -q "<url>" -O <local-name>`.
- The CDN's `robots.txt` returns 403 — this is expected and harmless.
- `--page-requisites` only follows `src` and `href` attributes. **Inline `background-image:url(...)` assets are NOT downloaded** — these must be extracted and fetched separately in Phase 2.
- Webflow uses **multiple CDN site IDs** — one for site-level assets (CSS, JS, images used in templates) and a separate one for CMS collection content (blog thumbnails, team photos, etc.). Check for multiple directories under `cdn.prod.website-files.com/` after mirroring.

### Phase 2: Consolidate into a Clean Structure

Create a deployable directory structure:

```
site/
  index.html
  privacy.html
  terms.html
  careers/          (preserve subdirectories)
  post/             (blog posts, etc.)
  assets/
    css/
    js/
    images/   (includes videos, SVGs, all media)
```

1. Copy HTML files from the `<domain>/` download directory to `site/`, **preserving any subdirectory structure** (e.g., `careers/`, `post/` for blog posts)
2. Copy CSS from `cdn.prod.website-files.com/<site-id>/css/` to `site/assets/css/`
3. Copy JS from `cdn.prod.website-files.com/<site-id>/js/` to `site/assets/js/`
4. Copy all images/media from **each** `cdn.prod.website-files.com/<site-id>/` directory to `site/assets/images/` — there are often multiple site IDs (one for site assets, another for CMS content)
5. **Extract and download missing `background-image` assets** — these are NOT downloaded by wget. Grep all HTML files for `background-image:url(` references pointing to `cdn.prod.website-files.com`, extract the URLs, and download them:

```bash
# Extract absolute CDN URLs from inline background-image styles
grep -roh 'cdn\.prod\.website-files\.com/[^"&)]*' site/ --include="*.html" | sed 's/&quot.*//' | sort -u > missing_urls.txt

# Download each one
while read url; do
  filename=$(basename "$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$url'))")")
  wget -q "https://$url" -O "site/assets/images/$filename"
  # Check for 0-byte files (double-encoding issue, see below)
done < missing_urls.txt
```

6. **Fix 0-byte downloads from double-encoded URLs** — Webflow double-encodes special characters in CMS filenames (`%2520` for space, `%252B` for `+`, `%2526` for `&`). If wget produces 0-byte files, retry with the double-encoded CDN URL:

```bash
# Find 0-byte image files
find site/assets/images -empty -type f
# Re-download using the double-encoded URL from the CDN
wget -q "https://cdn.prod.website-files.com/<site-id>/<double-encoded-filename>" -O "site/assets/images/<decoded-filename>"
```

7. Delete the raw wget download directories after consolidation

### Phase 3: Rewrite Asset URLs

The `--convert-links` flag rewrites URLs to relative paths like `../cdn.prod.website-files.com/<site-id>/...`. These need to be rewritten to match the new `assets/` structure.

**Important:** Pages in subdirectories (e.g., `careers/`, `post/`) need `../assets/` instead of `assets/`. Handle top-level and subdirectory pages separately.

**Step 1: Rewrite relative CDN paths (from `--convert-links`)**

```bash
# Top-level HTML files
sed -i '' 's|\.\./cdn\.prod\.website-files\.com/<SITE_ID>/css/|assets/css/|g' *.html
sed -i '' 's|\.\./cdn\.prod\.website-files\.com/<SITE_ID>/js/|assets/js/|g' *.html
sed -i '' 's|\.\./cdn\.prod\.website-files\.com/<SITE_ID>/|assets/images/|g' *.html
sed -i '' 's|\.\./cdn\.prod\.website-files\.com/[^/]*/|assets/images/|g' *.html

# Subdirectory HTML files (careers/, post/, etc.) — use ../assets/
sed -i '' 's|\.\./\.\./cdn\.prod\.website-files\.com/<SITE_ID>/css/|../assets/css/|g' subdir/*.html
sed -i '' 's|\.\./\.\./cdn\.prod\.website-files\.com/<SITE_ID>/js/|../assets/js/|g' subdir/*.html
sed -i '' 's|\.\./\.\./cdn\.prod\.website-files\.com/<SITE_ID>/|../assets/images/|g' subdir/*.html
sed -i '' 's|\.\./\.\./cdn\.prod\.website-files\.com/[^/]*/|../assets/images/|g' subdir/*.html
```

**Step 2: Rewrite absolute CDN URLs**

`--convert-links` only rewrites `src` and `href` attributes. Inline `background-image:url(...)` styles keep absolute CDN URLs and are NOT rewritten. Run a second pass for these:

```bash
# Top-level: absolute CDN URLs (no ../ prefix)
sed -i '' 's|cdn\.prod\.website-files\.com/[^/]*/|assets/images/|g' *.html

# Subdirectories
sed -i '' 's|cdn\.prod\.website-files\.com/[^/]*/|../assets/images/|g' subdir/*.html
```

**Step 3: Fix mangled `background-image:url()` inline styles**

This is the most common breakage. wget's `--convert-links` produces garbage for inline style URLs:
```
background-image:url(https://www.example.com/&quot;https://assets/images/file.jpg&quot;)
```

Fix with:
```bash
# Top-level pages
find . -maxdepth 1 -name "*.html" -exec sed -i '' \
  's|url(https://www\.<DOMAIN>/\&quot;https://assets/images/\([^&]*\)\&quot;|url(assets/images/\1|g' \
  {} \;

# Subdirectory pages — URL includes the subdirectory path
find ./post -name "*.html" -exec sed -i '' \
  's|url(https://www\.<DOMAIN>/post/\&quot;https://\.\./assets/images/\([^&]*\)\&quot;)|url(../assets/images/\1)|g' \
  {} \;
```

**Step 4: Fix double-encoded characters**

Webflow double-encodes special characters in CMS filenames. Fix these in HTML references:
```bash
# %2520 → %20 (space), %252B → %2B (+), %2526 → %26 (&)
find . -name "*.html" -exec sed -i '' 's/%2520/%20/g; s/%252B/%2B/g; s/%2526/%26/g' {} \;
```

**Step 5: Verify no CDN references remain**

```bash
grep -rc "cdn.prod.website-files.com" *.html subdir/*.html | grep -v ":0$"
```

Fix any remaining references — these are typically in `<meta>` OG tags or deeply nested inline styles.

### Phase 4: Fix Known Webflow Export Issues

These issues occur on virtually every Webflow migration:

#### 4a. Broken Video Sources

Webflow encodes video URLs with `%2F` in the path, which breaks during URL rewriting. The `<source>` tags end up truncated like `src="assets/images/>`.

**Fix:** Find all `<video>` elements and verify their `<source src="...">` attributes point to valid files. Also fix any `background-image:url(...)` poster references.

```python
# Use Python to extract and inspect video tags
import re
with open('index.html') as f:
    html = f.read()
for m in re.findall(r'<video[^>]*>.*?</video>', html, re.DOTALL):
    print(m)
```

#### 4b. Webflow Forms Don't Work

Webflow forms use `method="get"` with no action URL — they rely on Webflow's backend. They will NOT function on a self-hosted site.

**Options:**
- Remove forms entirely (replace with direct CTAs like App Store links)
- Replace with a form service (Formspree, Netlify Forms, Basin)
- Build a custom form handler

#### 4c. Outdated / Template Copy

Check for and update:
- "Coming Soon", "Join Waitlist", "Beta", "Early Access", "TestFlight" language
- Template placeholder links (e.g., koalaui.com from Webflow templates)
- Copyright year
- Broken email `mailto:` links where href domain differs from displayed text

```bash
# Quick audit for outdated language
python3 -c "
import re
with open('index.html') as f:
    html = f.read()
for term in ['waitlist', 'beta', 'early access', 'coming soon', 'testflight', 'koalaui']:
    count = html.lower().count(term)
    if count:
        print(f'{term}: {count}')
"
```

#### 4d. Webflow Data Attributes

These attributes serve no purpose without Webflow hosting and can be removed:
- `data-wf-domain`, `data-wf-page`, `data-wf-site` on `<html>`
- `data-wf-page-id`, `data-wf-element-id` on forms
- `<!-- Last Published: ... -->` HTML comments

These are cosmetic — removal is optional but keeps the HTML clean.

#### 4e. Propagate Edits Across All Pages

Webflow sites typically share the same header/footer across pages. If you edit the footer in `index.html` (e.g., removing forms, updating copyright), **you must apply the same edits to every other HTML page** (privacy.html, terms.html, etc.).

Also check that footer nav links on subpages point to `index.html#section` rather than `subpage.html#section`.

### Phase 5: Verify

Use `agent-browser` (if available) to visually verify the migrated site:

```bash
# Start a local server
python3 -m http.server 8080 -d ./site &

# Take screenshots and compare with the live site
agent-browser open http://localhost:8080/
agent-browser screenshot ./preview.png --full

agent-browser --session live open https://<DOMAIN>/
agent-browser --session live screenshot ./original.png --full
```

Also run a comprehensive asset reference check across **all** HTML files, including `background-image:url()` references:

```bash
python3 -c "
import re, os, urllib.parse

total_refs = 0
missing = []

for root, dirs, files in os.walk('site'):
    for fname in files:
        if not fname.endswith('.html'):
            continue
        fpath = os.path.join(root, fname)
        with open(fpath) as f:
            html = f.read()

        # Find src/href asset references
        refs = re.findall(r'(?:src|href)=\"((?:\.\./)*assets/[^\"]+)\"', html)
        # Find background-image url() references
        bg_refs = re.findall(r'url\(((?:\.\./)*assets/[^)]+)\)', html)

        for ref in refs + bg_refs:
            total_refs += 1
            file_dir = os.path.dirname(fpath)
            full_path = os.path.normpath(os.path.join(file_dir, urllib.parse.unquote(ref)))
            if not os.path.exists(full_path):
                missing.append((os.path.relpath(fpath, 'site'), ref))

print(f'{len(missing)} missing out of {total_refs} total asset references')
for fname, ref in missing:
    print(f'  MISSING in {fname}: {ref}')
"
```

This catches issues the old single-file check missed: subpage references, background-image URLs, and double-encoded filenames.

### Phase 6: Deploy

#### Render (Static Site)

```
Build command: echo 'No build required'
Publish path: ./site
```

Or use the Render MCP if available:

```
mcp__render__create_static_site(
  name: "<site-name>",
  repo: "https://github.com/<user>/<repo>.git",
  branch: "main",
  buildCommand: "echo 'No build required'",
  publishPath: "./site",
  autoDeploy: "yes"
)
```

#### Netlify

```bash
npx netlify-cli deploy --dir=./site --prod
```

#### Vercel

```bash
npx vercel ./site --prod
```

After deploying, update DNS records for the custom domain to point to the new host.

### Phase 7: Post-Migration Cleanup (Optional)

These are lower-priority improvements once the site is live:

- **Self-host external scripts** — jQuery from CloudFront, WebFont loader from Google
- **Remove unused Webflow JS modules** — the 500KB+ webflow runtime includes Lightbox, Slider, Lottie etc. that many sites don't use
- **Optimize images** — convert PNGs to WebP, fix oversized `sizes` attributes on responsive images
- **Replace Embedly YouTube embeds** — use direct YouTube iframes or click-to-load facades
- **Add `loading="eager"`** to above-the-fold hero images (Webflow sets all images to `lazy`)

## Limitations

- **JavaScript interactions** — Webflow's JS runtime (`webflow.*.js`) handles animations, tabs, dropdowns, etc. It will continue to work, but it's a monolithic ~500KB file. If you want to reduce this, you'd need to rewrite the interactions.
- **CMS content** — If the Webflow site uses CMS collections, the mirrored site captures the content as static HTML at the time of mirroring. Dynamic content won't update.
- **Forms** — As noted, Webflow forms won't work without their backend.
- **Site search** — Webflow's native search won't work. Use Algolia, Pagefind, or similar.
