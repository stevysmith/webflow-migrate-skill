---
name: website-builder-migrate
description: Migrate a site built on a website builder (Webflow, Framer, Squarespace, Wix, Carrd, etc.) to a self-hosted static site. Use when the user wants to export, migrate, or move a site off a website-builder platform without paying for an export, self-host the site, or transition to another hosting provider like Render, Netlify, or Vercel.
---

# Website Builder Migration

Migrate a live site built on a website-builder platform (Webflow, Framer, Squarespace, Wix, Carrd, Editor X, Dorik, etc.) to a self-hostable static site without needing a paid export. Uses `wget` to mirror the published site, then cleans up assets, URLs, and platform-specific artifacts.

## When to Use

- User wants to migrate off a website builder without paying for code export
- User wants to self-host a Webflow / Framer / Squarespace / Wix / Carrd site on Render, Netlify, Vercel, etc.
- User wants a local copy of a builder-hosted site they can edit and maintain

## Platform-Specific Notes

The Phase 1–7 workflow below is written against Webflow (the most common case and what's been battle-tested), but the same shape applies to other website builders. Before starting, identify the platform and substitute its CDN domain and chunk patterns.

| Platform | Asset CDN domain(s) | Notes |
|---|---|---|
| **Webflow** | `cdn.prod.website-files.com`, `d3e54v103j8qbb.cloudfront.net` (jQuery) | Multiple site-IDs per site (one for site assets, one for CMS content). Webpack chunks `webflow.achunk.<hash>.js`. Heavy SRI integrity tags — must strip. |
| **Framer** | `framerusercontent.com`, `framer.com/m/` | React SPA, dynamic imports of route bundles. Some pages may render client-side only — wget captures the SSR shell; verify hydration in the browser. Custom code blocks may reference external scripts. |
| **Squarespace** | `static1.squarespace.com`, `images.squarespace-cdn.com` | Heavy template JS (`sqs.js`), forms entirely backend-dependent. Many themes use server-side image transforms — capture each `?format=` variant referenced. |
| **Wix** | `static.parastorage.com`, `static.wixstatic.com` | Hardest to migrate — extremely SPA-driven, much of the page is rendered client-side from dynamic configs. wget mirroring often produces broken output; consider this approach only for static template sites. |
| **Carrd** | (mostly inlined / single-page) | Generally trivial — single HTML file with inlined CSS, few external assets. The full workflow is overkill; `wget --page-requisites <url>` plus a manual asset pass usually suffices. |

For unfamiliar platforms: open the live site, view source, and note (1) which CDN domain hosts CSS/JS/images, (2) whether `<script>` and `<link>` tags carry `integrity="sha384-..."` SRI attributes, (3) whether the runtime JS contains a webpack-style chunk-id-to-hash map. These three pieces drive Phases 1–3.

## Prerequisites

- The site must be **published and publicly accessible** (wget mirrors the live site)
- `wget` must be installed (comes with macOS/Linux)
- Optionally: `agent-browser` skill for visual verification

## Migration Workflow

Follow these phases in order. Each phase has specific steps — do not skip phases.

### Phase 1: Mirror the Live Site

Use `wget` with CDN spanning to download the full site including assets hosted on the builder's CDN. Substitute `<CDN_DOMAIN>` with the appropriate domain from the Platform-Specific Notes table (e.g. `cdn.prod.website-files.com` for Webflow, `framerusercontent.com` for Framer):

```bash
wget --mirror \
  --convert-links \
  --adjust-extension \
  --page-requisites \
  --span-hosts \
  --domains=<DOMAIN>,<CDN_DOMAIN> \
  --no-parent \
  https://<DOMAIN>/
```

**Key flags:**
- `--span-hosts --domains=...,<CDN_DOMAIN>` — required because the builder serves assets from a separate CDN domain
- `--convert-links` — rewrites absolute URLs to relative paths
- `--page-requisites` — downloads CSS, JS, images, fonts referenced by each page
- `--adjust-extension` — adds `.html` extensions for clean URLs

**Common issues (all platforms):**
- Videos with URL-encoded paths (`%2F`, `%20`) may not download automatically. Check for these and download manually with `wget -q "<url>" -O <local-name>`.
- The CDN's `robots.txt` may return 403 — this is expected and harmless.
- `--page-requisites` only follows `src` and `href` attributes. **Inline `background-image:url(...)` assets are NOT downloaded** — these must be extracted and fetched separately in Phase 2.
- **wget does NOT download dynamically-loaded webpack chunks** (e.g. `webflow.achunk.<hash>.js` on Webflow, `chunk-<hash>.js` or route bundles on Framer). The runtime loads these on demand for animations, sliders, route transitions, etc. Without them the page often renders blank. See Phase 2 step 8.
- Multi-tenant CDNs use **per-site IDs in the URL path** (e.g. Webflow's `cdn.prod.website-files.com/<site-id>/...`). A single site can have multiple IDs (one for site assets, one for CMS content). Check for multiple subdirectories under the CDN domain after mirroring.

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

8. **Download dynamically-loaded webpack chunks** — `wget` only fetches entry bundles. The runtime then loads additional chunks on demand (Webflow: `webflow.achunk.<hash>.js`; Framer/others: similar pattern with different naming). Without these, the page often renders blank because the entry bundle throws on the missing import. Each entry bundle has its own chunk-id-to-hash map.

To find the pattern, search the entry bundles for the chunk-URL builder (look for substrings like `achunk`, `chunk.`, or webpack's standard `r.u=e=>` / `__webpack_require__.u`). Extract the hash map (a JS object literal mapping chunk IDs to hashes), download each chunk from the same CDN path the entry bundle was served from.

**Worked example — Webflow:**

```bash
cd site/assets/js && python3 -c "
import re, glob
hashes = set()
for f in glob.glob('webflow.*.js'):
    if 'achunk' in f: continue
    s = open(f).read()
    for m in re.finditer(r'achunk\\.[\"\\x27]\\+\\((\\{[^}]{20,5000}?\\})', s):
        hashes.update(re.findall(r'[\"\\x27]([a-f0-9]{16})[\"\\x27]', m.group(1)))
for h in sorted(hashes): print(h)
" > /tmp/chunks.txt

while read h; do
  wget -q "https://cdn.prod.website-files.com/<SITE_ID>/js/webflow.achunk.$h.js" \
    -O "webflow.achunk.$h.js"
done < /tmp/chunks.txt
find . -name "webflow.achunk.*.js" -size 0   # any failures?
```

Webpack uses automatic publicPath (derived from the entry script `src`), so chunks just need to live alongside the entry bundles in `assets/js/`.

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

Fix any remaining references — these are typically in `<meta>` OG tags, `<link rel="preconnect">` hints, or deeply nested inline styles. Preconnect hints to the CDN can simply be removed.

**Step 6: Strip SRI `integrity` and `crossorigin` attributes**

Webflow (and most other website builders that ship hashed asset URLs) emit `<link>` and `<script>` tags with SHA-384 `integrity="..."` SRI hashes. The `--convert-links` flag in Phase 1 rewrites URLs *inside* the CSS files, which changes their byte content — so the original SRI hashes no longer match and **the browser silently blocks the CSS/JS**. Symptom: page renders blank with only raw text visible, console shows "Failed to find a valid digest in the 'integrity' attribute". Strip both attributes from every HTML file (skip if the platform doesn't use SRI; check by grepping for `integrity=` in any HTML file before deciding):

```bash
sed -i '' -E 's/ integrity="[^"]*"//g; s/ crossorigin="[^"]*"//g' *.html subdir/*.html
```

**Step 7: Rewrite font and asset paths inside CSS**

Webflow's CSS references fonts as `url(../<font>.ttf)` — assuming CSS at `<site>/css/` and fonts at `<site>/`. After consolidation, CSS lives at `assets/css/` so `..` resolves to `assets/`, but the fonts are in `assets/images/`. Rewrite the relative URLs (skip `data:` URIs):

```bash
cd assets/css && python3 -c "
import re, glob
for f in glob.glob('*.css'):
    s = open(f).read()
    new = re.sub(
        r'url\(\.\./([^/)][^/)]*\.(?:ttf|woff2?|otf|eot|svg|png|jpg|jpeg|gif|avif|webp))\)',
        r'url(../images/\1)', s)
    if new != s: open(f,'w').write(new); print('rewrote', f)
"
```

### Phase 4: Fix Known Builder Export Issues

These issues occur on virtually every website-builder migration. Most apply across platforms; a few are Webflow-specific (called out below).

#### 4a. Broken Video Sources

Webflow (and some other builders) encode video URLs with `%2F` in the path, which breaks during URL rewriting. The `<source>` tags end up truncated like `src="assets/images/>`.

**Fix:** Find all `<video>` elements and verify their `<source src="...">` attributes point to valid files. Also fix any `background-image:url(...)` poster references.

```python
# Use Python to extract and inspect video tags
import re
with open('index.html') as f:
    html = f.read()
for m in re.findall(r'<video[^>]*>.*?</video>', html, re.DOTALL):
    print(m)
```

#### 4b. Forms Don't Work

Builder forms (Webflow, Framer, Squarespace, Wix) all rely on the platform's backend — typically `method="get"` or `method="post"` with no real action URL, or with one that points back to the builder's API. They will NOT function on a self-hosted site.

**Options:**
- Remove forms entirely (replace with direct CTAs like email/App Store links)
- Replace with a form service (Formspree, Netlify Forms, Basin, Web3Forms)
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

#### 4d. Platform Metadata Attributes

These serve no purpose once self-hosted and can optionally be stripped:
- **Webflow:** `data-wf-domain`, `data-wf-page`, `data-wf-site` on `<html>`; `data-wf-page-id`, `data-wf-element-id` on forms; `<!-- Last Published: ... -->` HTML comments
- **Framer:** `data-framer-*` attributes on elements; `<meta name="generator" content="Framer ...">`
- **Squarespace:** `<meta name="generator" content="Squarespace">`; inline analytics tracking pixels pointing back to `squarespace.com`

These are cosmetic — removal is optional but keeps the HTML clean.

#### 4e. Propagate Edits Across All Pages

Builder-hosted sites typically share the same header/footer across pages. If you edit the footer in `index.html` (e.g., removing forms, updating copyright), **you must apply the same edits to every other HTML page**.

Also check that footer nav links on subpages point to `index.html#section` rather than `subpage.html#section`.

### Phase 5: Verify

**The static asset-reference check is necessary but not sufficient** — it can return "0 missing of N references" while the page renders blank because of SRI blocks, missing webpack chunks, or CSS-relative paths. Always do an in-browser check too.

Use `agent-browser` (if available) to visually verify the migrated site:

```bash
# Start a local server
python3 -m http.server 8080 -d ./site &

# Take screenshots and compare with the live site
agent-browser --session local open http://localhost:8080/
agent-browser --session local wait --load networkidle
agent-browser --session local screenshot ./preview.png --full

agent-browser --session live open https://<DOMAIN>/
agent-browser --session live wait --load networkidle
agent-browser --session live screenshot ./original.png --full
```

**Then check the browser console — this catches what static analysis cannot:**

```bash
agent-browser --session local errors        # JS errors (chunk-load failures, undefined refs)
agent-browser --session local console       # 404s, SRI integrity blocks, mixed-content blocks
# Or get all failed/zero-byte resource URLs in one shot:
agent-browser --session local eval "performance.getEntriesByType('resource').filter(r=>r.responseStatus>=400).map(r=>r.name)"
```

If the screenshot shows mostly blank space but the asset check passed, the most likely culprits are:
1. **SRI integrity blocking CSS/JS** — strip integrity/crossorigin (Phase 3, Step 6)
2. **Missing webpack chunks** — download `webflow.achunk.*.js` (Phase 2, Step 8)
3. **CSS `url(../foo.ttf)` paths broken** — rewrite to `url(../images/foo.ttf)` (Phase 3, Step 7)

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

- **Self-host external scripts** — jQuery from CloudFront, WebFont loader from Google, etc.
- **Remove unused builder JS modules** — Webflow's runtime is 500KB+ and includes Lightbox, Slider, Lottie etc. that many sites don't use; Framer ships per-route component bundles you can prune for static pages
- **Optimize images** — convert PNGs to WebP, fix oversized `sizes` attributes on responsive images
- **Replace Embedly YouTube embeds** — use direct YouTube iframes or click-to-load facades
- **Add `loading="eager"`** to above-the-fold hero images (Webflow and Framer both default to `lazy` on every image)

## Limitations

- **JavaScript interactions** — Webflow's JS runtime (`webflow.*.js`) handles animations, tabs, dropdowns, etc. It will continue to work, but it's a monolithic ~500KB file. If you want to reduce this, you'd need to rewrite the interactions.
- **CMS content** — If the Webflow site uses CMS collections, the mirrored site captures the content as static HTML at the time of mirroring. Dynamic content won't update.
- **Forms** — As noted, Webflow forms won't work without their backend.
- **Site search** — Webflow's native search won't work. Use Algolia, Pagefind, or similar.
