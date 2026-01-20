# Test Payloads for Push Action Buttons

This directory contains ready-to-use JSON payload files for testing dynamic push action buttons with apns-cli.

## Quick Start

```bash
cd /Klaviyo/Repos/apns-cli

# Send a test notification
apns-cli send \
  --token YOUR_DEVICE_TOKEN \
  --bundle-id YOUR_BUNDLE_ID \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_KEY_ID \
  --key-path /path/to/AuthKey_XXXXX.p8 \
  --payload /path/to/klaviyo-swift-sdk/test-payloads/1-basic-two-buttons.json
```

## Available Test Payloads

| File | Description | Buttons | Features |
|------|-------------|---------|----------|
| `1-basic-two-buttons.json` | Flash sale notification | Go to Settings, Go to Sign Up Forms | Basic 2-button layout |
| `2-three-mixed-buttons.json` | New arrivals | Go to Forms, Go to Push, Nothing | 3-button layout with mixed actions |
| `3-deep-linked-push-single-button.json` | Single button with deep link | See Forms | Single CTA with deep link |
| `4-error-case.json` | Invalid payload | Test Button | Missing mutable-content (should fallback) |

## Test Script

Save this as `send-test.sh`:

```bash
#!/bin/bash

# Configuration - UPDATE THESE VALUES
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

### Usage

```bash
chmod +x send-test.sh

# Send specific test
./send-test.sh test-payloads/1-basic-two-buttons.json
./send-test.sh test-payloads/2-three-mixed-buttons.json
./send-test.sh test-payloads/3-deep-linked-push-single-button.json
./send-test.sh test-payloads/4-error-case.json
```

## Verification Checklist

After sending a payload:

### Visual
- [ ] Notification appears in notification center
- [ ] Long-press or swipe shows action buttons
- [ ] Button labels are correct
- [ ] 2-button order is reversed (confirmatory action on right)

### Functional
- [ ] Tapping notification body opens default URL
- [ ] Tapping each button opens correct deep link
- [ ] App launches correctly

### Analytics
- [ ] `$opened_push` event tracked (body tap)
- [ ] `$opened_push_action` event tracked (button tap)
- [ ] Event contains `action_id` property
- [ ] Event contains `action_label` property

## Customization

To test with your own URLs, edit any JSON file and replace:
- `klaviyotest://` with your app's URL scheme
- Button labels with your desired text

## Troubleshooting

**Buttons don't appear:**
1. Check `mutable-content: 1` is set in payload
2. Verify NSE is configured correctly
3. Check device iOS version (iOS 10+ required)
4. Look for errors in Xcode console

**Events not tracked:**
1. Verify SDK is initialized in app
2. Check notification delegate is implemented
3. Wait a few minutes for events to appear in dashboard
4. Check Xcode console for event creation logs

**Deep links don't work:**
1. Verify URL scheme in Info.plist
2. Test URL in Safari first (should prompt to open app)
3. Check deep link handler implementation
4. Look for routing errors in console

## Full Documentation

See parent directory for complete documentation:
- `PUSH_ACTION_BUTTONS_PAYLOAD_SPEC.md` - Full payload specification
- `TEST_PAYLOADS.md` - Detailed testing guide
