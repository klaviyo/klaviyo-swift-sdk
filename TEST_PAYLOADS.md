# Test Payloads for Dynamic Push Action Buttons

This document contains ready-to-use APNs payloads for testing the dynamic push action button feature.

## Prerequisites

### Using apns-cli

```bash
# Navigate to apns-cli directory
cd /Users/ajay.subramanya/Klaviyo/Repos/apns-cli

# Send a test notification
apns-cli send \
  --token YOUR_DEVICE_TOKEN \
  --bundle-id YOUR_BUNDLE_ID \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_KEY_ID \
  --key-path /path/to/AuthKey_XXXXX.p8 \
  --payload payload.json
```

---

## Test Payload 1: Basic 2-Button Dynamic

**Scenario**: Flash sale with two action buttons

**File**: `1-basic-two-buttons.json`

```json
{
  "aps": {
    "alert": {
      "title": "⚡ Flash Sale!",
      "body": "50% off everything - 2 hours only!"
    },
    "mutable-content": 1,
    "sound": "default",
    "badge": 1
  },
  "body": {
    "_k": "test_flash_sale_001",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.shop",
        "label": "Go to Settings",
        "url": "klaviyotest://settings"
      },
      {
        "id": "com.klaviyo.test.later",
        "label": "Go to Sign Up Forms",
        "url": "klaviyotest://forms"
      }
    ]
  }
}
```

**Expected Behavior**:
- 2 buttons appear: [Go to Sign Up Forms] [Go to Settings] (reversed per iOS convention)
- Tapping "Go to Settings" → opens `klaviyotest://settings`
- Tapping "Go to Sign Up Forms" → opens `klaviyotest://forms`
- Event `$opened_push_action` tracked with `action_id` and `action_label`

---

## Test Payload 2: Three Mixed Buttons

**Scenario**: Three buttons with mixed actions including one without URL

**File**: `2-three-mixed-buttons.json`

```json
{
  "aps": {
    "alert": {
      "title": "New Arrivals Just for You",
      "body": "Check out our latest collection"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_new_arrivals_003",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.view",
        "label": "Go to Forms",
        "url": "klaviyotest://forms"
      },
      {
        "id": "com.klaviyo.test.favorites",
        "label": "Go to Push",
        "url": "klaviyotest://push"
      },
      {
        "id": "com.klaviyo.test.dismiss",
        "label": "Nothing"
      }
    ]
  }
}
```

**Expected Behavior**:
- 3 buttons appear in original order (no reversal for 3+ buttons)
- "Nothing" button has no URL (dismisses notification)

---

## Test Payload 3: Deep Linked Push Single Button

**Scenario**: Single button with deep link in notification body

**File**: `3-deep-linked-push-single-button.json`

```json
{
  "aps": {
    "alert": {
      "title": "Don't Miss Out!",
      "body": "Go to Settings"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "url": "klaviyotest://settings",
  "body": {
    "_k": "test_single_button_004",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.checkout",
        "label": "See Forms",
        "url": "klaviyotest://forms"
      }
    ]
  }
}
```

**Expected Behavior**:
- 1 button appears
- Tapping button opens `klaviyotest://forms`
- Tapping notification body opens `klaviyotest://settings` (from root `url` field)

---

## Test Payload 4: Error Case

**Scenario**: Invalid payload to test error handling

**File**: `4-error-case.json`

```json
{
  "aps": {
    "alert": "Missing mutable-content flag",
    "sound": "default"
  },
  "body": {
    "_k": "test_invalid_008",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.action",
        "label": "Test Button"
      }
    ]
  }
}
```

**Expected Behavior**:
- Notification displays WITHOUT buttons (missing `mutable-content: 1`)
- Should fallback gracefully

---

## Quick Test Script

Save this as `test-push.sh`:

```bash
#!/bin/bash

# Configuration
DEVICE_TOKEN="YOUR_DEVICE_TOKEN_HERE"
BUNDLE_ID="YOUR_BUNDLE_ID_HERE"
TEAM_ID="YOUR_TEAM_ID_HERE"
KEY_ID="YOUR_KEY_ID_HERE"
KEY_PATH="/path/to/AuthKey_XXXXX.p8"

# Path to payload (defaults to test 1)
PAYLOAD="${1:-test-payloads/1-basic-two-buttons.json}"

# Navigate to apns-cli
cd /Users/ajay.subramanya/Klaviyo/Repos/apns-cli

# Send notification
apns-cli send \
  --token "$DEVICE_TOKEN" \
  --bundle-id "$BUNDLE_ID" \
  --team-id "$TEAM_ID" \
  --key-id "$KEY_ID" \
  --key-path "$KEY_PATH" \
  --payload "../klaviyo-swift-sdk/$PAYLOAD"

echo "✅ Sent: $PAYLOAD"
```

**Usage**:
```bash
chmod +x test-push.sh
./test-push.sh test-payloads/1-basic-two-buttons.json  # Send payload 1
./test-push.sh test-payloads/2-three-mixed-buttons.json  # Send payload 2
./test-push.sh test-payloads/3-deep-linked-push-single-button.json  # Send payload 3
./test-push.sh test-payloads/4-error-case.json  # Send payload 4
```

---

## Verification Checklist

After sending a test payload, verify:

### Visual Verification
- [ ] Notification appears in notification center
- [ ] Long-press or swipe shows action buttons
- [ ] Button labels are correct
- [ ] Button count matches expected (1-4 buttons)
- [ ] 2-button order is reversed (confirmatory action on right)

### Functional Verification
- [ ] Tapping notification body opens default URL
- [ ] Tapping each button opens correct deep link
- [ ] App launches or brings to foreground
- [ ] Deep link routes to correct screen

### Analytics Verification
Check Klaviyo events dashboard for:
- [ ] `$opened_push` event (when body is tapped)
- [ ] `$opened_push_action` event (when button is tapped)
- [ ] `action_id` property contains button identifier
- [ ] `action_label` property contains button label text (dynamic only)

### Edge Cases
- [ ] Test without NSE implemented → fallback graceful
- [ ] Test with invalid payload → notification still displays
- [ ] Test with 128+ notifications → category pruning works

---

## Troubleshooting

### Buttons Don't Appear

1. Check `mutable-content: 1` is set
2. Verify NSE is configured correctly
3. Check console logs for parsing errors
4. Ensure `body._k` exists and is unique

### Events Not Tracked

1. Verify SDK is initialized
2. Check notification delegate is set
3. Look for events in Klaviyo dashboard (may have delay)
4. Check console logs for event creation

### Deep Links Don't Work

1. Verify URL scheme in Info.plist
2. Check deep link handler is implemented
3. Test URL in Safari first
4. Look for routing errors in console

---

## Next Steps

1. Copy desired payload to a JSON file
2. Update configuration in `test-push.sh`
3. Run the script to send notification
4. Verify behavior on device
5. Check analytics dashboard

For detailed payload specifications, see `PUSH_ACTION_BUTTONS_PAYLOAD_SPEC.md`.
