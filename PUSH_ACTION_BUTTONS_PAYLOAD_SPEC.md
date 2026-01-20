# Push Action Buttons - APNs Payload Specification

This document specifies the APNs payload format for dynamic push action buttons in the Klaviyo iOS SDK.

## Overview

The Klaviyo iOS SDK supports dynamic action buttons for push notifications, providing fully customizable button labels and actions per notification.

## Dynamic Action Buttons

### Requirements

- **`mutable-content: 1`** must be set in the `aps` dictionary
- Notification Service Extension (NSE) must be implemented
- iOS 10.0+ required

### Payload Structure

```json
{
  "aps": {
    "alert": {
      "title": "Flash Sale!",
      "body": "50% off everything - today only!"
    },
    "mutable-content": 1,
    "sound": "default",
    "badge": 1
  },
  "body": {
    "_k": "unique_notification_id_12345",
    "url": "myapp://home",
    "action_buttons": [
      {
        "id": "com.klaviyo.action.shop",
        "label": "Shop Now",
        "url": "myapp://sale/flash"
      },
      {
        "id": "com.klaviyo.action.later",
        "label": "Remind Later",
        "url": "myapp://reminders"
      }
    ]
  }
}
```

### Field Specifications

#### `aps.mutable-content`
- **Type**: Number
- **Required**: Yes
- **Value**: `1`
- **Purpose**: Triggers Notification Service Extension to process dynamic buttons

#### `body._k`
- **Type**: String
- **Required**: Yes
- **Purpose**: Unique identifier for the notification, used to generate category ID
- **Format**: Any unique string (UUID recommended)
- **Example**: `"notif_abc123_xyz789"`

#### `body.url`
- **Type**: String
- **Required**: No
- **Purpose**: Default deep link URL when user taps notification body (not a button)
- **Format**: Valid URL string (universal link or custom scheme)
- **Examples**:
  - `"myapp://home"`
  - `"https://example.com/products"`

#### `body.action_buttons`
- **Type**: Array of Objects
- **Required**: Yes (for dynamic buttons)
- **Min Length**: 1
- **Max Length**: 4 (iOS limit, recommend 2-3 for better UX)
- **Purpose**: Defines the action buttons to display

### Action Button Object

Each object in `action_buttons` array has these fields:

#### `id`
- **Type**: String
- **Required**: Yes
- **Purpose**: Unique identifier for this action (used in analytics)
- **Format**: Reverse domain notation recommended
- **Examples**:
  - `"com.klaviyo.action.shop"`
  - `"com.company.action.view_order"`
- **Used In**: `$opened_push_action` event as `action_id` property

#### `label`
- **Type**: String
- **Required**: Yes
- **Purpose**: Button text displayed to user
- **Max Length**: ~30 characters (iOS truncates longer text)
- **Localization**: Server should send localized text based on user's locale
- **Examples**:
  - `"Shop Now"` (English)
  - `"Comprar ahora"` (Spanish)
  - `"Jetzt einkaufen"` (German)

#### `url`
- **Type**: String
- **Required**: No
- **Purpose**: Deep link URL when this specific button is tapped
- **Format**: Valid URL string
- **Fallback**: If omitted, uses `body.url` as fallback
- **Examples**:
  - `"myapp://product/12345"`
  - `"https://example.com/cart"`
  - `"myapp://reminders/create"`

### Button Ordering

**iOS Convention (Applied Automatically by SDK):**
- **2 buttons**: Reversed (confirmatory action appears on right)
  - Sent: `["Decline", "Accept"]` → Displayed: `[Accept] [Decline]`
- **1 or 3+ buttons**: Original order preserved

**Recommendation:** Send buttons in logical order; SDK handles iOS conventions.

---

## Event Tracking

### Regular Notification Tap (Body Tap)

**Event**: `$opened_push`

**Properties**:
```json
{
  "event": "$opened_push",
  "properties": {
    "_k": "unique_notification_id",
    "url": "myapp://home",
    // ... other notification properties
  }
}
```

### Action Button Tap

**Event**: `$opened_push_action`

**Properties**:
```json
{
  "event": "$opened_push_action",
  "properties": {
    "_k": "unique_notification_id",
    "action_id": "com.klaviyo.action.shop",
    "action_label": "Shop Now",
    "url": "myapp://sale/flash",
    // ... other notification properties
  }
}
```

**Additional Properties**:
- `action_id`: The button's identifier
- `action_label`: The button's label text

---

## Validation Rules

### Dynamic Buttons

✅ **Valid:**
```json
{
  "aps": { "alert": "...", "mutable-content": 1 },
  "body": {
    "_k": "notif123",
    "action_buttons": [
      { "id": "action1", "label": "Button 1" }
    ]
  }
}
```

❌ **Invalid - Missing mutable-content:**
```json
{
  "aps": { "alert": "..." },  // ← Missing mutable-content: 1
  "body": {
    "action_buttons": [...]
  }
}
```

❌ **Invalid - Missing required fields:**
```json
{
  "body": {
    "action_buttons": [
      { "id": "action1" }  // ← Missing "label"
    ]
  }
}
```

❌ **Invalid - Missing notification ID:**
```json
{
  "body": {
    // ← Missing "_k"
    "action_buttons": [...]
  }
}
```

---

## Examples by Use Case

### E-commerce: Flash Sale

```json
{
  "aps": {
    "alert": {
      "title": "⚡ Flash Sale Alert",
      "body": "50% off everything for 2 hours only!"
    },
    "mutable-content": 1,
    "badge": 1
  },
  "body": {
    "_k": "flash_sale_2024_12_05",
    "url": "klaviyo://home",
    "action_buttons": [
      {
        "id": "com.klaviyo.action.shop",
        "label": "Shop Now",
        "url": "klaviyo://sale/flash"
      },
      {
        "id": "com.klaviyo.action.remind",
        "label": "Remind in 1hr",
        "url": "klaviyo://reminders/create?in=1h"
      }
    ]
  }
}
```

### E-commerce: Abandoned Cart

```json
{
  "aps": {
    "alert": {
      "title": "Your cart is waiting!",
      "body": "Complete your purchase and get free shipping."
    },
    "mutable-content": 1
  },
  "body": {
    "_k": "abandon_cart_user123_cart456",
    "url": "klaviyo://cart",
    "action_buttons": [
      {
        "id": "com.klaviyo.action.checkout",
        "label": "Complete Purchase",
        "url": "klaviyo://checkout"
      },
      {
        "id": "com.klaviyo.action.browse",
        "label": "Browse More",
        "url": "klaviyo://shop"
      }
    ]
  }
}
```

### E-commerce: Order Update

```json
{
  "aps": {
    "alert": {
      "title": "Package Delivered!",
      "body": "Your order #12345 was delivered."
    },
    "mutable-content": 1
  },
  "body": {
    "_k": "order_12345_delivered",
    "url": "klaviyo://orders/12345",
    "action_buttons": [
      {
        "id": "com.klaviyo.action.track",
        "label": "View Details",
        "url": "klaviyo://orders/12345/tracking"
      },
      {
        "id": "com.klaviyo.action.support",
        "label": "Contact Support",
        "url": "klaviyo://support/order/12345"
      }
    ]
  }
}
```

### E-commerce: Back in Stock

```json
{
  "aps": {
    "alert": {
      "title": "Good news!",
      "body": "The Nike Air Max you wanted is back in stock."
    },
    "mutable-content": 1
  },
  "body": {
    "_k": "restock_product_abc123",
    "url": "klaviyo://product/abc123",
    "action_buttons": [
      {
        "id": "com.klaviyo.action.buy",
        "label": "Buy Now",
        "url": "klaviyo://product/abc123/quick-buy"
      },
      {
        "id": "com.klaviyo.action.view",
        "label": "View Product",
        "url": "klaviyo://product/abc123"
      }
    ]
  }
}
```

---

## Testing Payloads

### Using apns-cli

```bash
# Install if needed
npm install -g apns-cli

# Send test notification
apns-cli send \
  --token YOUR_DEVICE_TOKEN \
  --bundle-id com.your.app \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_KEY_ID \
  --key-path /path/to/AuthKey_XXXXX.p8 \
  --payload payload.json
```

### Sample Test Payload (payload.json)

```json
{
  "aps": {
    "alert": "Test notification with action buttons",
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_notification_001",
    "url": "klaviyo://test",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.action1",
        "label": "Action 1",
        "url": "klaviyo://test/action1"
      },
      {
        "id": "com.klaviyo.test.action2",
        "label": "Action 2",
        "url": "klaviyo://test/action2"
      }
    ]
  }
}
```

---

## Best Practices

### Button Labels

✅ **Good**:
- "Shop Now" - Clear call-to-action
- "View Details" - Specific action
- "Track Order" - User benefit clear

❌ **Avoid**:
- "Click Here" - Vague
- "Learn More About Our Amazing Products" - Too long
- "Button 1" - Not descriptive

### Button Count

- **Recommended**: 2 buttons
  - Clean UI, easy to tap
  - Works well on all device sizes
- **Acceptable**: 1 or 3 buttons
  - 1 button: Simple yes/no scenarios
  - 3 buttons: Rare, ensure labels are short
- **Avoid**: 4 buttons
  - Crowded interface
  - Small tap targets

### Deep Link URLs

✅ **Good**:
- Specific screens: `"myapp://product/12345"`
- With context: `"myapp://sale/flash?source=push"`
- Fallback handling: Always set `body.url` as default

❌ **Avoid**:
- Generic: `"myapp://"`
- Invalid URLs: `"not a url"`
- External links without handling: `"https://example.com"` (opens Safari)

### Localization

- **Server-side**: Send localized button labels based on user's locale
- **A/B Testing**: Test different button labels for engagement

### Category IDs

- **Dynamic**: Auto-generated as `com.klaviyo.dynamic.<notification_id>`
- **Namespace**: Always use `com.klaviyo.*` prefix
- **Avoid Conflicts**: Don't use `com.klaviyo.*` for custom app categories

---

## Troubleshooting

### Buttons Don't Appear

**Check**:
1. ✅ `mutable-content: 1` is set
2. ✅ NSE is implemented and calls `KlaviyoExtensionSDK.handleNotificationServiceDidReceivedRequest(...)`
3. ✅ `body._k` exists
4. ✅ `body.action_buttons` is an array with valid objects
5. ✅ Each button has `id` and `label`

### Button Taps Not Tracked

**Check**:
1. ✅ App delegate implements `userNotificationCenter(_:didReceive:withCompletionHandler:)`
2. ✅ Calls `KlaviyoSDK().handle(notificationResponse:withCompletionHandler:)`
3. ✅ Check Klaviyo events dashboard for `$opened_push_action` events

### Deep Links Not Working

**Check**:
1. ✅ URL scheme registered in Info.plist
2. ✅ Universal links configured (if using https://)
3. ✅ App implements deep link handling via `action: .openDeepLink(url)`
4. ✅ Button `url` field is valid URL string

---

## Support

For issues or questions:
- SDK Issues: [GitHub Issues](https://github.com/klaviyo/klaviyo-swift-sdk/issues)
- Integration Help: Klaviyo Support
- Payload Testing: Use `apns-cli` from `/Users/ajay.subramanya/Klaviyo/Repos/apns-cli`
