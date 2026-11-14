#!/usr/bin/env bash
# Publishes the website to GitHub Pages by updating the gh-pages branch with a fresh build.
# Human-run. Only ever touches the gh-pages branch, never main. Keeps a published v1/ folder (the signed rules).
# Usage: ./scripts/publish-site.sh
set -euo pipefail
cd "$(dirname "$0")/.."

node scripts/build-site.mjs dist-site

TMP="$(mktemp -d)"
cleanup() { git worktree remove --force "$TMP" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git fetch -q origin gh-pages
  git worktree add -q -B gh-pages "$TMP" origin/gh-pages
else
  git worktree add -q --orphan -b gh-pages "$TMP"
fi

# Replace everything except git's own files and the rules folder.
find "$TMP" -mindepth 1 -maxdepth 1 -not -name .git -not -name v1 -exec rm -rf {} +
cp -R dist-site/. "$TMP"/
touch "$TMP/.nojekyll"

git -C "$TMP" add -A
if git -C "$TMP" diff --cached --quiet; then
  echo "site unchanged"
else
  git -C "$TMP" commit -q -m "Publish site"
  git -C "$TMP" push -q origin gh-pages
  echo "published to the gh-pages branch"
fi
