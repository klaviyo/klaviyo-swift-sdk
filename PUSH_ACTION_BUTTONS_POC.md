# Push Action Buttons POC

## Overview

This POC implements push notification action buttons support for the Klaviyo iOS SDK, following the same pattern as Braze. Action buttons allow users to interact with push notifications directly without opening the app (e.g., "Accept/Decline", "Yes/No", "View/Dismiss").

## Implementation Summary

### 1. **Predefined Categories** (`PushActionCategories.swift`)

Four predefined button categories (matching Braze's defaults):
- Accept/Decline
- Yes/No
- Confirm/Cancel
- View/Dismiss

Each category has namespaced identifiers to prevent conflicts:
- Category IDs: `com.klaviyo.category.*`
- Action IDs: `com.klaviyo.action.*`

### 2. **Registration API** (`PushCategoryRegistration.swift`)

Developers must explicitly register categories (like Braze):

```swift
// Register all categories
Klaviyo.shared.registerPushCategories(Set(KlaviyoPushCategory.allCases))

// Or register specific ones
Klaviyo.shared.registerPushCategories([.acceptDecline, .yesNo])
```

**Smart Merge**: SDK intelligently merges with existing categories, never overwrites developer's custom categories.

### 3. **Notification Response Parsing** (`UNNotificationResponse+Klaviyo.swift`)

New computed properties:
- `isActionButtonTap`: Detects action button vs default tap
- `klaviyoActionIdentifier`: Returns Klaviyo action ID if applicable
- `actionButtonURL`: Extracts action-specific deep link from payload
- `actionButtonMetadata`: Returns all action-specific metadata

### 4. **Event Tracking** (`Event.swift`)

New internal event type:
- `_openedPushAction` → `$opened_push_action`
- Includes `action_id` property with the button identifier

Existing event unchanged:
- `_openedPush` → `$opened_push` (backwards compatible)

### 5. **Automatic Handling** (`Klaviyo.swift`)

Enhanced `handle(notificationResponse:withCompletionHandler:)`:
- Detects action button taps automatically
- Tracks appropriate event (`_openedPush` vs `_openedPushAction`)
- Handles action-specific deep links
- Fully backwards compatible

## APNs Payload Structure

```json
{
  "aps": {
    "alert": "Your order has shipped!",
    "category": "com.klaviyo.category.viewDismiss"
  },
  "body": {
    "_k": "unique_id",
    "url": "myapp://default",
    "actions": {
      "com.klaviyo.action.view": {
        "url": "myapp://orders/12345"
      },
      "com.klaviyo.action.dismiss": {}
    }
  }
}
```

## Developer Integration

### Step 1: Register Categories

```swift
// In AppDelegate.application(_:didFinishLaunchingWithOptions:)
Klaviyo.initialize(apiKey: "YOUR_API_KEY")

// Register push categories
Klaviyo.shared.registerPushCategories([
    .acceptDecline,
    .yesNo,
    .viewDismiss
])
```

### Step 2: Handle Notifications (No Changes Needed!)

```swift
// Existing code works as-is
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    // SDK automatically detects action buttons and tracks events
    _ = Klaviyo.shared.handle(
        notificationResponse: response,
        withCompletionHandler: completionHandler
    )
}
```

### Step 3: (Optional) Custom Logic Before SDK

```swift
func userNotificationCenter(...) {
    // Developer can add custom logic first
    if response.actionIdentifier == "com.klaviyo.action.view" {
        // Custom handling (network call, analytics, etc.)
        trackInternalAnalytics()
    }

    // Then let Klaviyo track and handle URLs
    _ = Klaviyo.shared.handle(...)
}
```

## What SDK Handles Automatically

✅ **Event Tracking**: Tracks `$opened_push_action` with action identifier
✅ **Deep Link Routing**: Opens action-specific URLs automatically
✅ **Backwards Compatibility**: Regular push taps still work as before
✅ **Smart Category Merge**: Doesn't overwrite developer's custom categories

## Test Coverage

Comprehensive test suite (`PushActionButtonTests.swift`):
- Category identifiers and creation
- Action button detection
- URL extraction for actions
- Event tracking verification
- Backwards compatibility
- Edge cases (missing data, invalid URLs)

## Design Decisions

### Why Manual Registration (Like Braze)?

**Pros**:
- No risk of overwriting developer's categories
- Clear developer intent
- Follows industry standard (Braze pattern)
- Simple and predictable

**Cons**:
- Requires one extra method call
- Developer must understand the flow

### Why Smart Merge?

Prevents conflicts by checking existing categories before registering. If a category with the same ID exists, it's kept (not overwritten).

### Why Automatic URL/Deep Link Handling?

Matches existing SDK behavior for regular push taps. SDK already handles deep links automatically, so action buttons should too. Developers can still add custom logic before calling SDK.

## Next Steps for Full Implementation

1. ✅ Core functionality (DONE in POC)
2. 🔜 Dynamic category registration from payload
3. 🔜 Rich input actions (text input, etc.)
4. 🔜 Localization support for button titles
5. 🔜 Analytics dashboard integration
6. 🔜 Public documentation and guides
7. 🔜 Example app with various use cases

## Testing Plan

### Manual Testing
1. Register categories in test app
2. Send push with category identifier
3. Tap action buttons
4. Verify events tracked with correct action_id
5. Verify deep links open correctly
6. Test backwards compatibility (regular taps)

### Automated Testing
- ✅ Unit tests for all new functionality
- 🔜 Integration tests with test app
- 🔜 UI tests for button interactions

## Files Modified/Created

**New Files**:
- `Sources/KlaviyoSwift/PushNotifications/PushActionCategories.swift`
- `Sources/KlaviyoSwift/PushNotifications/PushCategoryRegistration.swift`
- `Tests/KlaviyoSwiftTests/PushActionButtonTests.swift`

**Modified Files**:
- `Sources/KlaviyoSwift/Klaviyo.swift` - Enhanced notification handler
- `Sources/KlaviyoSwift/Utilities/UNNotificationResponse+Klaviyo.swift` - Action parsing
- `Sources/KlaviyoSwift/Models/Event.swift` - New event type

## Comparison with Braze

| Feature | Braze | Klaviyo POC | Status |
|---------|-------|-------------|--------|
| Predefined categories | 4 (Accept/Decline, Yes/No, Confirm/Cancel, More) | 4 (same + View/Dismiss) | ✅ |
| Manual registration | Yes | Yes | ✅ |
| Automatic registration | Optional | Not implemented | 🔜 |
| Event tracking | Yes | Yes | ✅ |
| URL/Deep link handling | Yes | Yes | ✅ |
| Custom categories | Yes | Smart merge support | ✅ |
| Analytics dashboard | Yes | Not implemented | 🔜 |

## Known Limitations (POC)

- Static categories only (no dynamic from payload)
- English button titles only (no localization)
- No rich input actions (text, authentication, etc.)
- No custom button icons
- No analytics dashboard integration

These are intentionally out of scope for the POC and can be added in full implementation.
