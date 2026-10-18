#!/usr/bin/env bash
# Checks that the latest "iOS SDK CI" (swift.yml) run on a commit completed successfully.
# Usage: scripts/check-ci-green.sh <commit-sha-or-ref>
# Needs `gh` with a token that can read Actions (GH_TOKEN) and GH_REPO (or a checkout of the repo).
# Exits 1 when no CI run exists, the latest run is still in progress, or it did not succeed.
set -euo pipefail

REF="${1:?usage: check-ci-green.sh <commit-sha-or-ref>}"
REPO="${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

SHA=$(gh api "repos/$REPO/commits/$REF" --jq .sha)
latest=$(gh api "repos/$REPO/actions/workflows/swift.yml/runs?head_sha=$SHA&per_page=1" \
  --jq '.workflow_runs[0] | select(. != null) | "\(.status)|\(.conclusion)|\(.html_url)"')

if [ -z "$latest" ]; then
  echo "❌ No iOS SDK CI run found on $SHA ($REF)"
  exit 1
fi

IFS='|' read -r status conclusion url <<< "$latest"
if [ "$status" = "completed" ] && [ "$conclusion" = "success" ]; then
  echo "✅ iOS SDK CI passed on $SHA ($REF): $url"
  exit 0
fi

echo "❌ iOS SDK CI on $SHA ($REF) is $status/${conclusion:-none}: $url"
exit 1
