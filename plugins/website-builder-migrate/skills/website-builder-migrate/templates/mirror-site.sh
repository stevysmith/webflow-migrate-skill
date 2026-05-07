#!/bin/bash
# Template: Mirror a Webflow site for self-hosting
# Usage: ./mirror-site.sh <domain> [output-dir]

set -euo pipefail

DOMAIN="${1:?Usage: $0 <domain> [output-dir]}"
OUTPUT_DIR="${2:-./site}"
DOMAIN_CLEAN="${DOMAIN#https://}"
DOMAIN_CLEAN="${DOMAIN_CLEAN#http://}"
DOMAIN_CLEAN="${DOMAIN_CLEAN%/}"

echo "=== Mirroring $DOMAIN_CLEAN ==="

# Phase 1: wget mirror with CDN spanning
wget --mirror \
  --convert-links \
  --adjust-extension \
  --page-requisites \
  --span-hosts \
  --domains="$DOMAIN_CLEAN,cdn.prod.website-files.com" \
  --no-parent \
  "https://$DOMAIN_CLEAN/" 2>&1 || true

# Phase 2: Identify the Webflow site ID from the CDN directory
SITE_ID=$(ls cdn.prod.website-files.com/ 2>/dev/null | head -1)
if [[ -z "$SITE_ID" ]]; then
  echo "ERROR: No CDN assets downloaded. Check the domain and try again."
  exit 1
fi
echo "Detected Webflow site ID: $SITE_ID"

# Phase 3: Consolidate into clean structure
mkdir -p "$OUTPUT_DIR/assets/css" "$OUTPUT_DIR/assets/js" "$OUTPUT_DIR/assets/images"

# Copy HTML files
cp "$DOMAIN_CLEAN"/*.html "$OUTPUT_DIR/" 2>/dev/null || true

# Copy CSS
find "cdn.prod.website-files.com/$SITE_ID" -name "*.css" -exec cp {} "$OUTPUT_DIR/assets/css/" \;

# Copy JS
find "cdn.prod.website-files.com/$SITE_ID" -name "*.js" -exec cp {} "$OUTPUT_DIR/assets/js/" \;

# Copy all media files
find "cdn.prod.website-files.com" -type f \
  \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.svg" \
     -o -name "*.webp" -o -name "*.gif" -o -name "*.mp4" -o -name "*.webm" \
     -o -name "*.ico" -o -name "*.PNG" -o -name "*.JPG" -o -name "*.JPEG" \) \
  -exec cp {} "$OUTPUT_DIR/assets/images/" \;

# Phase 4: Rewrite asset URLs in HTML files
cd "$OUTPUT_DIR"
for html_file in *.html; do
  [[ -f "$html_file" ]] || continue

  # CSS paths
  sed -i '' "s|\.\./cdn\.prod\.website-files\.com/$SITE_ID/css/|assets/css/|g" "$html_file"
  # JS paths
  sed -i '' "s|\.\./cdn\.prod\.website-files\.com/$SITE_ID/js/|assets/js/|g" "$html_file"
  # Image/asset paths (specific site ID first)
  sed -i '' "s|\.\./cdn\.prod\.website-files\.com/$SITE_ID/|assets/images/|g" "$html_file"
  # Catch any remaining CDN references
  sed -i '' 's|\.\./cdn\.prod\.website-files\.com/[^/]*/|assets/images/|g' "$html_file"
done
cd - > /dev/null

# Phase 5: Clean up raw download directories
rm -rf "$DOMAIN_CLEAN" cdn.prod.website-files.com

# Report
TOTAL_FILES=$(find "$OUTPUT_DIR" -type f | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
HTML_COUNT=$(find "$OUTPUT_DIR" -name "*.html" | wc -l | tr -d ' ')
REMAINING_CDN=$(grep -rl "cdn.prod.website-files.com" "$OUTPUT_DIR"/*.html 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "=== Migration Complete ==="
echo "Output:     $OUTPUT_DIR"
echo "Files:      $TOTAL_FILES"
echo "Size:       $TOTAL_SIZE"
echo "HTML pages: $HTML_COUNT"
echo ""

if [[ "$REMAINING_CDN" -gt 0 ]]; then
  echo "WARNING: $REMAINING_CDN HTML file(s) still reference cdn.prod.website-files.com"
  echo "These are likely URL-encoded video/poster URLs that need manual fixing."
  echo "Run: grep 'cdn.prod.website-files.com' $OUTPUT_DIR/*.html"
fi

echo ""
echo "Next steps:"
echo "  1. Fix any remaining CDN references (see WARNING above)"
echo "  2. Check video <source> tags are not truncated"
echo "  3. Update/remove Webflow forms"
echo "  4. Update outdated copy (waitlist, beta, etc.)"
echo "  5. Verify with: python3 -m http.server 8080 -d $OUTPUT_DIR"
