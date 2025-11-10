# AI Agent Guidelines

This file provides guidance to AI coding agents (Claude Code, Cursor, GitHub Copilot, etc.) when
working with code in this repository.

AI agents should assume the role of an experienced iOS/Swift developer with a background in mobile app
development and SDK engineering. You are familiar with Swift, iOS development, SwiftPM/CocoaPods, and best practices
in software engineering. You will be asked to help with code reviews, feature implementations, and debugging issues
in the Klaviyo Swift SDK. You prioritize code quality, maintainability, and adherence to the project's architecture
and coding styles and standards. You create reusable code, searching for existing implementations first, and if you see
conflicting or duplicative methods of doing similar tasks, refactor common functionality into shared helpers/utilities.
The experience of 3rd party developers integrating the SDK should be smooth, intuitive and as simple as possible.
You prefer solutions using the most modern, practical and efficient approaches available in the Swift/iOS ecosystem.

## Intro

This is the Swift SDK for Klaviyo, a marketing automation platform. The SDK is designed to be modular,
allowing developers to integrate various features including analytics, push notifications, in-app messaging (forms),
and extension support (app clips, watch kits, etc.).

The SDK uses Swift Package Manager for distribution and supports multiple platforms including iOS,
tvOS, macOS, watchOS, and visionOS.

## Common Commands

### Build Commands

```bash
# Build the entire package
swift build

# Build in release mode
swift build -c release

# Build for a specific platform (from Xcode)
xcodebuild build -scheme klaviyo-swift-sdk-Package -destination "platform=iOS Simulator,name=iPhone 15 Pro"

# Build specific module
xcodebuild build -scheme KlaviyoSwift -destination "platform=iOS Simulator"
```

### Test Commands

```bash
# Run all tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Run tests via Makefile (recommended)
make test-all

# Run tests in debug configuration
make CONFIG=debug test-library

# Run tests in release configuration
make CONFIG=release test-library

# Run specific test suite from Xcode
xcodebuild test -scheme klaviyo-swift-sdk-Package -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

### Linting & Formatting Commands

```bash
# Run SwiftLint analysis
swiftlint

# Run SwiftLint with strict rules
swiftlint lint

# Automatically fix SwiftLint violations where possible
swiftlint --autocorrect

# Format code with SwiftFormat
swiftformat .

# Run both linting and formatting (via pre-commit)
swiftlint && swiftformat .
```

### Installation

```bash
# Install dependencies for development
gem install bundler
bundle install

# Install SwiftLint and SwiftFormat (via Homebrew)
brew install swiftlint swiftformat
```

## Architecture Overview

The Klaviyo Swift SDK is organized into multiple modules, each with specific responsibilities:

### Module Structure

1. **KlaviyoCore Module**:
    - Foundation for other modules
    - Provides shared utilities, networking, configuration management, and state persistence
    - Contains models for API communication and internal data structures
    - Networking layer for all API calls to Klaviyo's servers
    - Vendor code for any third-party integrations

2. **KlaviyoSwift Module** (Main Analytics):
    - Main entry point via the `Klaviyo` class
    - Handles profile identification and event tracking
    - Manages user state and batches API requests for performance
    - State management for user profiles, attributes, and preferences
    - Public API for developers integrating the SDK

3. **KlaviyoForms Module** (In-App Messaging):
    - Handles in-app form rendering and interaction
    - Connects to Klaviyo's CDN for form content
    - Manages form display timing and user interaction
    - WebView-based form presentation
    - Utilities for form lifecycle management

4. **KlaviyoSwiftExtension Module**:
    - Support for app extensions (app clips, watch kits, notification services, etc.)
    - Lightweight version of SDK for extension targets
    - Supports push notification handling from extensions

### Key Components

1. **Klaviyo Class** (`Klaviyo.swift`):
    - Singleton facade for SDK functionality
    - Main public API for developers integrating the SDK
    - Handles initialization and profile management
    - Entry point for analytics and forms

2. **KlaviyoState**:
    - Manages current profile information
    - Persists data between app sessions using UserDefaults or Keychain
    - Thread-safe access to profile state

3. **KlaviyoAPI**:
    - Handles communication with Klaviyo's Client APIs
    - Batches requests for efficiency
    - Provides retry logic and error handling
    - URLSession-based networking

4. **Profile & Event Models**:
    - Data models for user profiles and events
    - Codable for JSON serialization
    - Type-safe representation of Klaviyo data

## Development Workflow

### CI/CD Pipeline

The project uses GitHub Actions for CI/CD, particularly for running tests and linting checks on pull requests.
Ensure that all tests pass and lint checks are successful before committing any changes.
Do not use `--no-verify` as a way to work around pre-commit hooks unless explicitly prompted.

The pre-commit hook configuration (`.pre-commit-config.yaml`) enforces:
- SwiftLint compliance
- SwiftFormat formatting
- File size limits
- No merge conflicts

### Testing Approach

As with production code, when writing tests be DRY. Find common setup, verify, and teardown code
that can be reused across tests. Use shared test utilities and fixtures where possible.

The SDK uses XCTest for unit testing with the following structure:

- `*Tests.swift` for each implementation class
- Organize tests into test classes that inherit from `XCTestCase`
- Mock external dependencies and network calls
- Test both happy paths and error cases
- Use XCTestExpectation for async testing
- Prefer verifying side effects and state changes over exact implementation details

### Code Style

The project enforces the Swift code style using SwiftLint and SwiftFormat with customizations:

- All code must pass SwiftLint checks before merging
- SwiftFormat is used to maintain consistent code formatting
- Maximum line length is 110 characters
- Disable certain SwiftLint rules as specified in `.swiftlint.yml`

Other style guidelines:

- Extract common logic into extensions or utility classes
- Use value types (structs) for models and enums for options
- Avoid force unwrapping (`!`) - use optional binding, nil coalescing (`??`), or guard statements instead
- Avoid magic strings/numbers, preferring constants, enums and static properties
- Prefer computed properties over methods when there are no side effects
- Use trailing closures for better readability
- Follow Swift API Design Guidelines for naming conventions

### Import Organization

- Import statements should be organized alphabetically
- Group Foundation/standard library imports separately from third-party imports
- Use specific imports; avoid wildcard imports

### Integration Points

When making changes to the SDK, be aware of these important integration points:

1. Public API surfaces (particularly in `Klaviyo.swift`)
2. Version management in Package.swift and podspec files
3. CocoaPods distribution (KlaviyoSwift.podspec)
4. SwiftPM distribution (Package.swift)
5. Platform-specific code and availability attributes
6. Extension-compatible code (KlaviyoSwiftExtension)

## Logging Guidelines

Logging should follow a structured approach with clear severity levels:

| Level       | Use For                                                          |
|-------------|------------------------------------------------------------------|
| **Verbose** | Troubleshooting: detailed flow updates, minor state transitions  |
| **Debug**   | Diagnostics: service status transitions, configuration details   |
| **Info**    | Significant events or user actions                               |
| **Warning** | Degraded functionality with fallback, retries, missing resources |
| **Error**   | Operational failures, unrecoverable errors, exceptions           |

When adding logging:
- Use consistent log tags/prefixes for categorization
- Include relevant context (user IDs, event types, etc.) for debugging
- Avoid logging sensitive user data (PII)
- Consider logging performance metrics for critical paths

## Testing Platforms and Devices

The SDK should be tested across multiple platforms and iOS versions:

- iOS: iPhone simulators (iPhone 15 Pro is standard in CI)
- tvOS, macOS, watchOS, visionOS where applicable
- Minimum iOS version: As specified in Package.swift
- Latest stable Xcode version (currently 15.2)

## Documentation & Comments

- Use MARK: comments to organize code sections in large files
- Document public APIs with documentation comments (///)
- Explain non-obvious algorithmic choices
- Keep comments up-to-date when changing implementation

## Performance Considerations

- Be mindful of main thread operations - use background threads for networking
- Use lazy initialization for expensive resources
- Batch API requests to minimize network overhead
- Consider memory usage in long-running features
- Profile code with Xcode Instruments when optimizing

## Platform-Specific Code

Use availability attributes for platform-specific functionality:

```swift
@available(iOS 14.0, *)
func newAPIMethod() {
    // Implementation
}
```

Keep extension-compatible code in KlaviyoSwiftExtension module to support app extensions
which have stricter limitations.

## Release Process

Before releasing:
1. Update version numbers in Package.swift and podspec files
2. Update MIGRATION_GUIDE.md if there are breaking changes
3. Ensure all tests pass
4. Run SwiftLint and SwiftFormat
5. Create a release tag with appropriate version number
6. Update changelog/release notes

## Troubleshooting Common Issues

### Tests Failing Locally but Passing in CI
- Ensure you're using the correct Xcode version (15.2)
- Clear derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Ensure proper iOS Simulator is selected

### SwiftLint Violations
- Run `swiftlint --autocorrect` for automatic fixes
- Review `.swiftlint.yml` for custom rules
- Some violations may need manual fixes

### Build Failures
- Update SwiftPM dependencies: `swift package update`
- Ensure minimum deployment target matches Package.swift settings
- Check for platform-specific code issues with `#available` checks
