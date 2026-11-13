#!/usr/bin/env bash
# Builds a release archive for TestFlight. Human-run only: needs your Apple Developer account in Xcode.
# Usage: ./scripts/archive.sh [--bump]
#   --bump  raises CURRENT_PROJECT_VERSION by one first (TestFlight needs a new build number per upload).
# Then upload from Xcode: Window, Organizer, pick the archive, Distribute App, TestFlight and App Store.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--bump" ]]; then
  CURRENT=$(sed -n 's/^    CURRENT_PROJECT_VERSION: "\([0-9]*\)"/\1/p' project.yml)
  NEXT=$((CURRENT + 1))
  sed -i '' "s/^    CURRENT_PROJECT_VERSION: \"$CURRENT\"/    CURRENT_PROJECT_VERSION: \"$NEXT\"/" project.yml
  echo "build number $CURRENT -> $NEXT"
fi

./scripts/verify.sh
xcodegen generate

OUT="build/QuietFeed.xcarchive"
rm -rf "$OUT"
xcodebuild archive \
  -project QuietFeed.xcodeproj -scheme QuietFeed \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT" \
  -allowProvisioningUpdates -quiet

echo
echo "archive ready: $OUT"
echo "Open it with: open $OUT   (it appears in Xcode's Organizer)"
