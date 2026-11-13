#!/usr/bin/env bash
# Builds and uploads a TestFlight build. Human-authorised: the release loop only runs it after
# the owner ticks H12 in the Build Plan. Needs the App Store Connect API key (see TestFlight Checklist).
# Usage: ./scripts/testflight-upload.sh [--dry-run]
#   --dry-run  runs the preflight and stops, uploading nothing.
# Each upload raises CURRENT_PROJECT_VERSION by one, commits that change locally and does not push.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

ENV_FILE="${QF_ASC_ENV:-$HOME/.quietfeed-asc.env}"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  [[ -n "${!v:-}" ]] || { echo "missing $v (set it in $ENV_FILE)"; exit 1; }
done
[[ -f "$ASC_KEY_PATH" ]] || { echo "key file not found: $ASC_KEY_PATH"; exit 1; }

echo "==> preflight"
if ! OUT=$(./scripts/testflight-preflight.sh 2>&1); then
  echo "$OUT" | tail -2
  echo "preflight is not READY, not uploading"; exit 3
fi
echo "$OUT" | tail -1
[[ $DRY -eq 1 ]] && { echo "dry run: ready to upload, nothing sent"; exit 0; }

echo "==> tests"
./scripts/verify.sh

echo "==> bump build number"
CURRENT=$(sed -n 's/^    CURRENT_PROJECT_VERSION: "\([0-9]*\)"/\1/p' project.yml)
NEXT=$((CURRENT + 1))
sed -i '' "s/^    CURRENT_PROJECT_VERSION: \"$CURRENT\"/    CURRENT_PROJECT_VERSION: \"$NEXT\"/" project.yml
xcodegen generate >/dev/null

TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Local.xcconfig | tr -d ' \r')
WORK="build/upload"
rm -rf "$WORK"; mkdir -p "$WORK"

xcodebuild archive -project QuietFeed.xcodeproj -scheme QuietFeed -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/QuietFeed.xcarchive" \
  -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -quiet

cat >"$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST

echo "==> uploading build $NEXT"
xcodebuild -exportArchive -archivePath "$WORK/QuietFeed.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/out" \
  -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"

git add project.yml
git commit -q -m "Build $NEXT: uploaded to TestFlight

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
echo "uploaded build $NEXT. It shows in App Store Connect, TestFlight, after Apple finishes processing (often 10 to 30 minutes)."
