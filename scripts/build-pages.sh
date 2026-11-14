#!/usr/bin/env bash
# Builds the folder that GitHub Pages serves: the website plus a signed v1/rulepack.json.
# Needs RULES_SIGNING_KEY (the private key PEM text) in the environment. It is never printed or written to disk.
# Usage: ./scripts/build-pages.sh [output-folder]   (default: site)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-site}"

if [[ -z "${RULES_SIGNING_KEY:-}" ]]; then
  echo "build-pages: RULES_SIGNING_KEY is empty. Add it as a GitHub Actions secret (see the Build Plan, H16)." >&2
  exit 1
fi

node scripts/validate-rules.mjs rules/rulepack.json

# The whole site (landing page, privacy page, styles) plus the signed rules under v1/.
node scripts/build-site.mjs "$OUT"
mkdir -p "$OUT/v1"
node scripts/sign-rules.mjs --in rules/rulepack.json --out "$OUT/v1/rulepack.json"
touch "$OUT/.nojekyll"

VERSION=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("rules/rulepack.json","utf8")).packVersion)')
echo "built $OUT (pack version $VERSION)"
