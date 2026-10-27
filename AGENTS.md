# AI Agent Guidelines

This file provides guidance to AI coding agents (Claude Code, Cursor, GitHub Copilot, etc.) when
working with code in this repository.

Assume the role of an experienced iOS/Swift SDK engineer familiar with Swift, SwiftPM, CocoaPods, and TCA.
Prioritize code quality, maintainability, and reuse — search for existing implementations before adding new ones.
Keep the 3rd-party developer integration experience smooth and simple.

## Intro

This is the Swift SDK for Klaviyo, a marketing automation platform. The SDK is designed to be modular,
allowing developers to integrate various features including analytics, push notifications, in-app messaging (forms),
and extension support (for rich push and badge count).

## Common Commands

### Build Commands

```bash
# Build for iOS Simulator
xcodebuild build -scheme klaviyo-swift-sdk-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro"

# Build specific module
xcodebuild build -scheme KlaviyoSwift -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

### Test Commands

```bash
# Run tests via xcodebuild directly
xcodebuild test -scheme klaviyo-swift-sdk-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro"

# Run tests in debug configuration
make test-library

# Run tests in release configuration
make CONFIG=release test-library
```

### Linting & Formatting Commands

```bash
# Run SwiftLint with auto-fix and strict mode (what pre-commit uses)
swiftlint --fix --strict

# Run SwiftFormat
swiftformat .
```

### Code Review

CodeRabbit is active on this repo and auto-reviews PRs. It reads this file as a code guidelines
source. When performing code reviews, avoid re-surfacing findings CodeRabbit may have already flagged.
If you notice patterns worth encoding as review guidance, suggest adding them to `.coderabbit.yaml`.

### Commits & Pull Requests
If prompted to commit, push, or open pull requests:

- Keep commit messages concise
- Open pull requests in **draft** mode first unless otherwise directed
- Use the PR template at `.github/pull_request_template.md`
- Include a brief changelog and test plan with reproducible steps

### Branch Naming & PR Targets

| Prefix | Purpose | May target `master` directly |
|--------|---------|------------------------------|
| `rel/*` | Release branches | Yes |
| `ci/*` | CI/tooling changes (GitHub Actions, scripts, build config) | Yes |
| `docs/*` | Documentation-only changes | Yes |
| `feat/*` | New features | No — target active `rel/*` |
| `{initials}/*` | Personal/WIP branches | No — target active `rel/*` |

A required status check blocks merges to `master` from any branch not in the allowed list. A conventional-commit PR title prefixed with `ci:`, `chore:`, `docs:`, or `rel:` (case-insensitive, scopes allowed) also satisfies the check. The check posts a comment with retargeting instructions and applies a `needs: release branch` label. To bypass in exceptional cases, a maintainer can add the `manual-merge` label — use sparingly.

## Architecture Overview

The SDK uses [The Composable Architecture](https://www.pointfree.co/collections/composable-architecture) framework. It is
split into separate modules: `KlaviyoSwift` (analytics, push), `KlaviyoForms` (in-app messaging), `KlaviyoLocation` (geofencing), `KlaviyoSwiftExtension` (rich push, badge count), `KlaviyoCore` (shared internals), and `KlaviyoAutomaticPushBootstrap` (Objective-C shim for automatic push setup, shipped inside `KlaviyoSwift`).

### Repository Layout

Each top-level directory below has its own `AGENTS.md` with directory-specific guidance.

- `Sources/`: one directory per SwiftPM target (see `Package.swift`)
- `Tests/`: one XCTest target per module, plus snapshot fixtures
- `Examples/`: sample apps (SPM, SPM automatic push, CocoaPods) that consume the SDK
- `fastlane/`: legacy podspec release lanes
- `scripts/`: release and CI helper scripts used by GitHub Actions
- `*.podspec`: one CocoaPods spec per module; must stay in sync with `Package.swift` targets
- `bump-version.sh`: updates the SDK version everywhere it is hard-coded
- `README.md`, `MIGRATION_GUIDE.md`, `PUSH_NOTIFICATION_DATA_GUIDE.md`: public integration docs

### Adding or Changing a Module

SwiftPM and CocoaPods are both supported, so module changes usually need edits in two places:

- `Package.swift` (targets, dependencies, resources)
- the matching `*.podspec` (`source_files`, `resource_bundles`, `dependency`, and the
  `-package-name` flags in `pod_target_xcconfig` that make `package`-level access work under CocoaPods)

### Versioning & Releases

- The SDK version lives in `Sources/KlaviyoCore/Utils/Version.swift` and in every `*.podspec`.
  Use `./bump-version.sh <version>` to update all of them (it also updates test snapshots,
  example app Podfile and Xcode project versions). The script uses BSD `sed -i ''`, so run it on macOS.
- `scripts/check-version.sh <version>` verifies `Version.swift` and podspecs agree; CI runs it on `rel/*` branches.
- Releases are published through the `publish-release.yml` workflow
  (`gh workflow run publish-release.yml -f version=X.Y.Z`), which dispatches CocoaPods publishing and SPM verification.

### Testing Approach

As with production code, when writing tests be DRY. Extract common setup, teardown, and assertion
helpers into shared test utilities and fixtures.

Test file naming follows `*Tests.swift` per implementation class.

- Use TCA's `TestStore` for reducer and effect testing.
- Prefer verifying side effects and state changes over exact implementation details
- A common test pattern uses `SnapshotTesting` (`pointfreeco/swift-snapshot-testing`). Verify generated snapshots match expectations after code changes.

### Code Style

The project enforces Swift code style using SwiftLint and SwiftFormat with customizations:

- Maximum line length is 110 characters
- Certain SwiftLint rules are disabled — see `.swiftlint.yml`

Other style guidelines:

- Extract common logic into extensions or utility classes
- Use value types (structs) for models and enums for options
- Avoid magic strings/numbers, preferring constants, enums and static properties
