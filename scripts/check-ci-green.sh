#!/usr/bin/env bash
# Checks that the latest "iOS SDK CI" (swift.yml) run passed for a commit.
# Usage: scripts/check-ci-green.sh <commit-sha-or-ref>
# Checks runs on the commit itself first. When there are none and the commit is a PR merge commit,
# checks the PR's head commit instead, since swift.yml runs on pull_request but not on pushes to
# rel/* branches.
# Needs `gh` with a token that can read Actions and pull requests (GH_TOKEN), and GH_REPO (or a
# checkout of the repo). Exits 1 when no CI run exists, the latest run is still in progress, or it
# did not succeed.
set -euo pipefail

REF="${1:?usage: check-ci-green.sh <commit-sha-or-ref>}"
REPO="${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

SHA=$(gh api "repos/$REPO/commits/$REF" --jq .sha)

latest_run() {
  gh api "repos/$REPO/actions/workflows/swift.yml/runs?head_sha=$1&per_page=1" \
    --jq '.workflow_runs[0] | select(. != null) | "\(.status)|\(.conclusion)|\(.html_url)"'
}

CI_SHA="$SHA"
latest=$(latest_run "$SHA")
if [ -z "$latest" ]; then
  PR_HEAD=$(gh api "repos/$REPO/commits/$SHA/pulls" \
    --jq "[.[] | select(.merge_commit_sha == \"$SHA\")][0].head.sha // empty")
  if [ -n "$PR_HEAD" ]; then
    echo "No iOS SDK CI run on $SHA; it is a PR merge commit, so checking the PR head $PR_HEAD"
    CI_SHA="$PR_HEAD"
    latest=$(latest_run "$PR_HEAD")
  fi
fi

if [ -z "$latest" ]; then
  echo "❌ No iOS SDK CI run found on $CI_SHA ($REF)"
  exit 1
fi

IFS='|' read -r status conclusion url <<< "$latest"
if [ "$status" = "completed" ] && [ "$conclusion" = "success" ]; then
  echo "✅ iOS SDK CI passed on $CI_SHA ($REF): $url"
  exit 0
fi

echo "❌ iOS SDK CI on $CI_SHA ($REF) is $status/${conclusion:-none}: $url"
exit 1
