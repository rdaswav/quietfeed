#!/usr/bin/env bash
# Pushes rules/rulepack.json to the NAS. Human-run only; the build loop never runs this
# without --dry-run. Uses tar over ssh because scp is disabled on the NAS.
# Usage: ./scripts/deploy-rules.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

HOST="${QF_NAS_HOST:-nas}"
REMOTE_DIR="${QF_REMOTE_DIR:-/volume1/docker/quietfeed/rules}"

# 1. Validate locally first. Never deploy a bad pack.
node scripts/validate-rules.mjs rules/rulepack.json

# 2. Push.
PUSH="COPYFILE_DISABLE=1 tar -C rules -cf - rulepack.json | ssh $HOST \"mkdir -p $REMOTE_DIR && tar -C $REMOTE_DIR -xf -\""

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run, nothing was sent:"
  echo "  $PUSH"
  exit 0
fi

echo "deploying to $HOST:$REMOTE_DIR"
tar -C rules -cf - rulepack.json | ssh "$HOST" "mkdir -p $REMOTE_DIR && tar -C $REMOTE_DIR -xf -"
echo "done. Pull to refresh in the app's Settings."
