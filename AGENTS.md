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

### Documentation Commands

```bash
# Build the combined DocC site for KlaviyoSwift, KlaviyoForms, KlaviyoLocation, KlaviyoSwiftExtension
make docs DOCS_BASE_PATH=klaviyo-swift-sdk/5.6   # output: build/docs/site

# Build, then serve at http://localhost:8000/<DOCS_BASE_PATH>/documentation/
make docs-serve DOCS_BASE_PATH=klaviyo-swift-sdk/5.6

# Local demo: build for the root path and serve at http://localhost:8000
make docs-preview

# Fail on any DocC warning
make docs DOCC_STRICT=1
```

- Each documented product has a catalog at `Sources/<Product>/<Product>.docc`. Add articles there.
- `scripts/build-docs.sh` uses `xcodebuild docbuild` + `docc merge`, not `swift-docc-plugin`,
  because the package depends on UIKit and can't build for the host.
- The script documents every library product in `Package.swift`. `KlaviyoCore` isn't a product, so
  its own `public` declarations (cross-module plumbing) get no pages. A product's public extensions
  on `KlaviyoCore` types, such as `registerForInAppForms` on `KlaviyoSDKModule`, do appear under that
  product's "Extended Modules".
- Don't use `@_documentation(visibility:)` to hide a symbol yet. The pinned SwiftFormat (0.51.2)
  reads the access keyword inside it as an ACL and rewrites both the attribute and the members.
- A catalog can link to its own module and to modules that module imports, such as
  ``` ``KlaviyoCore/KlaviyoSDKModule/registerGeofencing()`` ```. It can't link to sibling products
  (e.g. `KlaviyoSDK` from `KlaviyoForms`). Use code voice for those.

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

A required status check blocks merges to `master` from any branch not in the allowed list. A conventional-commit PR title prefixed with `ci:`, `chore:`, `docs:`, or `rel:` (case-insensitive, scopes allowed) also satisfies the check. The check judges each PR by its own base branch, read from the GitHub API. It doesn't use `github.base_ref`, which reports the stack's base for a PR inside a GitHub stack, so a PR stacked on another PR's branch is not treated as targeting `master`. The check posts a comment with retargeting instructions and applies a `needs: release branch` label. To bypass in exceptional cases, a maintainer can add the `manual-merge` label — use sparingly.

## Architecture Overview

The SDK uses [The Composable Architecture](https://www.pointfree.co/collections/composable-architecture) framework. It is
split into separate modules: `KlaviyoSwift` (analytics, push), `KlaviyoForms` (in-app messaging), `KlaviyoLocation` (geofencing), `KlaviyoSwiftExtension` (rich push, badge count), `KlaviyoUI` (UI components), and `KlaviyoCore` (shared internals).

### Testing Approach

As with production code, when writing tests be DRY. Extract common setup, teardown, and assertion
helpers into shared test utilities and fixtures.

Test file naming follows `*Tests.swift` per implementation class.

- Use TCA's `TestStore` for reducer and effect testing.
- Prefer verifying side effects and state changes over exact implementation details
- A common test pattern uses `SnapshotTesting` (`pointfreeco/swift-snapshot-testing`). Verify generated snapshots match expectations after code changes.

### UI Test IDs

- Give every interactive or asserted-on control in `Examples/` a snake_case `accessibilityIdentifier` (e.g. `push_log_clear_button`).
- Check existing names before adding an ID, and reuse the shared name when the same control exists in the other SDK example apps.
- When you rename or remove a control, update its ID and every test or automation that references it.

### Code Style

The project enforces Swift code style using SwiftLint and SwiftFormat with customizations:

- Maximum line length is 120 characters
- Certain SwiftLint rules are disabled — see `.swiftlint.yml`

Other style guidelines:

- Extract common logic into extensions or utility classes
- Use value types (structs) for models and enums for options
- Avoid magic strings/numbers, preferring constants, enums and static properties
