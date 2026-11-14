#!/usr/bin/env bash
# Builds the folder that GitHub Pages serves: a signed v1/rulepack.json and a short index.html.
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

rm -rf "$OUT"
mkdir -p "$OUT/v1"
node scripts/sign-rules.mjs --in rules/rulepack.json --out "$OUT/v1/rulepack.json"

VERSION=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("rules/rulepack.json","utf8")).packVersion)')
cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Quiet Feed rules</title>
</head>
<body>
  <h1>Quiet Feed rules</h1>
  <p>This page serves the signed hide rules that the Quiet Feed app checks for. Current pack version: ${VERSION}.</p>
  <p>The rules are plain data and the app only accepts them if the signature matches a key built into the app.</p>
  <p><a href="https://github.com/rdaswav/quietfeed">Source and issues</a></p>
</body>
</html>
HTML

echo "built $OUT (pack version $VERSION)"
