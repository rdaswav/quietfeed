#!/usr/bin/env bash
# Answers one question: could a TestFlight upload work right now?
# Archives the app, then exports it for App Store Connect WITHOUT uploading. That export is
# where Apple's signing rules (including the Family Controls distribution entitlement) bite.
#
# Exit codes: 0 ready, 3 blocked (reason printed on the last line), 1 something else went wrong.
# Output ends with one line: "STATUS: READY" or "STATUS: BLOCKED: <reason>".
set -uo pipefail
cd "$(dirname "$0")/.."

fail() { echo "STATUS: ERROR: $1"; exit 1; }

TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Local.xcconfig 2>/dev/null | tr -d ' \r')
[[ -n "$TEAM" && "$TEAM" != "XXXXXXXXXX" ]] || fail "Local.xcconfig has no DEVELOPMENT_TEAM"
command -v xcodegen >/dev/null || fail "xcodegen is not installed"

# Optional credentials, kept outside the repo.
ENV_FILE="${QF_ASC_ENV:-$HOME/.quietfeed-asc.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
AUTH=()
HAVE_KEY=0
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "${ASC_KEY_PATH:-/nonexistent}" ]]; then
  echo "credentials: present"
  HAVE_KEY=1
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
else
  echo "credentials: missing (needed only for the upload, see TestFlight Checklist)"
fi

xcodegen generate >/dev/null || fail "xcodegen generate failed"

WORK="build/preflight"
rm -rf "$WORK"; mkdir -p "$WORK"

echo "archiving..."
xcodebuild archive -project QuietFeed.xcodeproj -scheme QuietFeed -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/QuietFeed.xcarchive" \
  -allowProvisioningUpdates -quiet >"$WORK/archive.log" 2>&1 \
  || { tail -5 "$WORK/archive.log"; fail "archive failed, see $WORK/archive.log"; }

cat >"$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

echo "exporting for App Store Connect (not uploading)..."
if xcodebuild -exportArchive -archivePath "$WORK/QuietFeed.xcarchive" \
     -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" \
     -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} >"$WORK/export.log" 2>&1; then
  echo "STATUS: READY"
  exit 0
fi

# Turn Apple's error into one readable reason.
if grep -qi "family" "$WORK/export.log"; then
  echo "STATUS: BLOCKED: the Family Controls distribution entitlement is not approved for this team yet"
  echo "(full log: $WORK/export.log)"
  exit 3
fi
if [[ $HAVE_KEY -eq 0 ]] && grep -q "No Accounts" "$WORK/export.log"; then
  echo "STATUS: BLOCKED: no App Store Connect API key, so the command line cannot sign for distribution and the entitlement could not be checked"
  echo "(full log: $WORK/export.log)"
  exit 3
fi
REASON=$(grep -iE "error:|doesn.t (include|support)|entitlement|no profiles|not (registered|found|available)" "$WORK/export.log" \
  | sed -E 's/^[^:]*(error: )?//' | head -3 | tr '\n' ' ' | cut -c1-300)
[[ -n "$REASON" ]] || REASON=$(tail -3 "$WORK/export.log" | tr '\n' ' ' | cut -c1-300)
echo "STATUS: BLOCKED: $REASON"
echo "(full log: $WORK/export.log)"
exit 3
