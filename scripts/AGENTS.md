# scripts

Bash helpers called by the GitHub Actions release workflows. You can also run them locally from the
repo root.

- `check-version.sh <version>`: checks that `Sources/KlaviyoCore/Utils/Version.swift` and every
  `*.podspec` contain `<version>`. Used by `swift-release.yml` and `publish-release.yml`. When
  `GITHUB_ENV` is set it exports variables for later Slack notification steps.
- `check-ci-green.sh <sha-or-ref>`: checks via `gh api` that the latest `swift.yml` ("iOS SDK CI") run for a commit
  passed. For a PR merge commit it falls back to the PR head commit. Needs `gh` auth (`GH_TOKEN`) and
  `GH_REPO` or a checkout. Used by `publish-release.yml` and `spm-verify.yml`.
- `spm-verify.sh <tag> [work-dir]`: creates a throwaway SwiftPM package that depends on a
  **published** tag and builds all four products for iOS Simulator. `SPM_VERIFY_REPO_URL` overrides
  the repo URL. Used by `spm-verify.yml`.

## Conventions

- Start each script with `#!/usr/bin/env bash`, a header comment with usage, and `set -euo pipefail`
  (`check-version.sh` deliberately omits `-e` so it can report every mismatch).
- Required arguments use the `"${1:?usage: ...}"` pattern.
- Keep logic here rather than inline in workflow YAML so it can be run and tested locally.
