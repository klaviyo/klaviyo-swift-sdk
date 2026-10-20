#!/usr/bin/env bash
# Checks that the latest "iOS SDK CI" (swift.yml) run passed for a commit.
# Usage: scripts/check-ci-green.sh <commit-sha-or-ref>
# When the commit is the merge commit of a PR, checks the PR's head commit instead, since swift.yml
# runs on pull_request but not on pushes to rel/* branches.
# Needs `gh` with a token that can read Actions and pull requests (GH_TOKEN), and GH_REPO (or a
# checkout of the repo). Exits 1 when no CI run exists, the latest run is still in progress, or it
# did not succeed.
set -euo pipefail

REF="${1:?usage: check-ci-green.sh <commit-sha-or-ref>}"
REPO="${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

SHA=$(gh api "repos/$REPO/commits/$REF" --jq .sha)
CI_SHA=$(gh api "repos/$REPO/commits/$SHA/pulls" \
  --jq "[.[] | select(.merge_commit_sha == \"$SHA\")][0].head.sha // empty")
if [ -n "$CI_SHA" ]; then
  echo "$SHA is a PR merge commit; checking CI on the PR head $CI_SHA"
else
  CI_SHA="$SHA"
fi

latest=$(gh api "repos/$REPO/actions/workflows/swift.yml/runs?head_sha=$CI_SHA&per_page=1" \
  --jq '.workflow_runs[0] | select(. != null) | "\(.status)|\(.conclusion)|\(.html_url)"')

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
