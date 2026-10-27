# Examples

Sample iOS apps that show how to integrate the SDK. They are not part of the SDK build or the
`make test-library` run. `Package.swift` here is an empty placeholder package. It stops SwiftPM from
treating this directory as part of the root package.

See `KlaviyoSwiftExamples/README.md` for what each app demonstrates.

## Layout (`KlaviyoSwiftExamples/`)

- `Shared/`: SwiftUI/UIKit app code (`KLMuncheryApp`, login, menu, cart, push log, deep linking)
  compiled into every example app. Most example changes belong here.
- `SPMExample/`: Xcode project that consumes the SDK as a **local** Swift package
  (relative path back to the repo root), so it builds against your working copy. It has two app targets:
  `SPMExample` (manual push integration) and `SPMExampleAutomatic` (opts in through the
  `klaviyo_automatic_push_open_tracking` / `klaviyo_automatic_push_token_forwarding` Info.plist keys).
  Each has its own Notification Service Extension.
- `CocoapodsExample/`: consumes **published** pods pinned in `Podfile`. Run `pod install` in that
  directory and open the `.xcworkspace`. It does not pick up local source changes.

## Conventions

- `bump-version.sh` updates the pod versions in `CocoapodsExample/Podfile` and `MARKETING_VERSION` in
  both Xcode projects. Don't bump them by hand.
- `Pods/` is excluded from pre-commit.
- Keep the examples aligned with the integration steps in the root `README.md`. If a public API or
  integration step changes, update the examples too.
