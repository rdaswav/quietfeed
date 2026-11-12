#!/usr/bin/env bash
# Single acceptance gate. Usage: ./scripts/verify.sh [--fast]
set -euo pipefail
cd "$(dirname "$0")/.."

FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

stage() { echo; echo "==> $1"; }
skip() { echo "    skipped: $1"; }

# 1. Core logic
stage "swift test (QuietFeedCore)"
if [[ -d Packages/QuietFeedCore ]]; then
  (cd Packages/QuietFeedCore && swift test)
else
  skip "Packages/QuietFeedCore does not exist"
fi

# 2. Injected JS
stage "node tests (web)"
if [[ -f web/package.json ]]; then
  [[ -d web/node_modules ]] || npm install --prefix web
  npm test --prefix web
else
  skip "web/package.json does not exist"
fi

# 3. Rule pack
stage "validate rule pack"
if [[ -f scripts/validate-rules.mjs && -f rules/rulepack.json ]]; then
  node scripts/validate-rules.mjs rules/rulepack.json
else
  skip "validator or rules/rulepack.json does not exist"
fi

if [[ $FAST -eq 1 ]]; then
  echo; echo "verify (fast): OK"
  exit 0
fi

# 4. Build and integration tests
stage "xcodegen generate"
if [[ -f project.yml ]]; then
  xcodegen generate
else
  skip "project.yml does not exist"
  echo; echo "verify: OK"
  exit 0
fi

DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
for rt,devs in sorted(d.items()):
    if "iOS" not in rt: continue
    for x in devs:
        if x["name"].startswith("iPhone") and x.get("isAvailable",True):
            print(x["udid"]); sys.exit(0)
')
if [[ -z "$DEVICE_ID" ]]; then echo "no available iPhone simulator"; exit 1; fi
DEST="platform=iOS Simulator,id=$DEVICE_ID"

stage "xcodebuild build"
xcodebuild build -project QuietFeed.xcodeproj -scheme QuietFeed -destination "$DEST" -quiet

stage "xcodebuild test (AppTests)"
if [[ -d AppTests ]]; then
  xcodebuild test -project QuietFeed.xcodeproj -scheme QuietFeed -destination "$DEST" -quiet
else
  skip "AppTests does not exist"
fi

echo; echo "verify: OK"
