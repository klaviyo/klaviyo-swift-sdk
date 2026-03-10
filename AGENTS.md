# AI Agent Guidelines

This file provides guidance to AI coding agents (Claude Code, Cursor, GitHub Copilot, etc.) when
working with code in this repository.

Assume the role of an experienced iOS/Swift SDK engineer familiar with Swift, SwiftPM, CocoaPods, and TCA. Prioritize code quality, maintainability, and reuse — search for existing implementations before adding new ones. The 3rd-party developer integration experience should be smooth and simple.

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

### Commits & Pull Requests
If prompted to commit, push, or open pull requests:

- Keep commit messages concise
- Open pull requests in **draft** mode first unless otherwise directed
- Use the PR template at `.github/pull_request_template.md`
- Include a brief changelog and test plan with reproducible steps

## Architecture Overview

The SDK uses [The Composable Architecture](https://www.pointfree.co/collections/composable-architecture) framework. It is
split into separate modules: `KlaviyoSwift` (analytics, push), `KlaviyoForms` (in-app messaging), `KlaviyoLocation` (geofencing), `KlaviyoSwiftExtension` (rich push, badge count), `KlaviyoUI` (UI components), and `KlaviyoCore` (shared internals).

### Testing Approach

As with production code, when writing tests be DRY. Find common setup, verify, and teardown code
that can be reused across tests. Use shared test utilities and fixtures where possible.

Test file naming follows `*Tests.swift` per implementation class.

- Use TCA's `TestStore` for reducer and effect testing.
- Prefer verifying side effects and state changes over exact implementation details
- A common test pattern uses `SnapshotTesting` (`pointfreeco/swift-snapshot-testing`). Verify generated snapshots match expectations after code changes.

### Code Style

The project enforces the Swift code style using SwiftLint and SwiftFormat with customizations:

- All code must pass SwiftLint checks before merging
- SwiftFormat is used to maintain consistent code formatting
- Maximum line length is 110 characters
- Disable certain SwiftLint rules as specified in `.swiftlint.yml`

Other style guidelines:

- Extract common logic into extensions or utility classes
- Use value types (structs) for models and enums for options
- Avoid magic strings/numbers, preferring constants, enums and static properties
