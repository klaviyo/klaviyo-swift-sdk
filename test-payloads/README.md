# Test Payloads for Push Action Buttons

This directory contains ready-to-use JSON payload files for testing dynamic push action buttons with apns-cli.

## Quick Start

```bash
cd /Users/ajay.subramanya/Klaviyo/Repos/apns-cli

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
| `1-basic-two-buttons.json` | Flash sale notification | Shop Now, Remind Later | Basic 2-button layout |
| `2-with-icons.json` | Order delivered | View Details, Contact Support | SF Symbols icons (iOS 15+) |
| `3-three-buttons.json` | New arrivals | Browse All, Favorites, Not Now | 3-button layout |
| `4-single-button.json` | Cart reminder | Complete Purchase | Single CTA |
| `5-abandoned-cart.json` | Cart recovery | Checkout, Keep Shopping | E-commerce scenario |
| `6-back-in-stock.json` | Product availability | Buy Now, View Product | Stock alert |
| `7-predefined-fallback.json` | Order shipped | View, Dismiss | Predefined categories (no mutable-content) |
| `8-hybrid.json` | Special offer | Claim Offer, No Thanks | Both dynamic + predefined |
| `9-localization-spanish.json` | Spanish language | Comprar Ahora, Recordar Después | Localization example |
| `10-error-case.json` | Invalid payload | Test Button | Missing mutable-content (should fallback) |

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
./send-test.sh test-payloads/2-with-icons.json
./send-test.sh test-payloads/5-abandoned-cart.json
```

## Verification Checklist

After sending a payload:

### Visual
- [ ] Notification appears in notification center
- [ ] Long-press or swipe shows action buttons
- [ ] Button labels are correct
- [ ] Icons appear (iOS 15+) or gracefully absent
- [ ] 2-button order is reversed (confirmatory action on right)

### Functional
- [ ] Tapping notification body opens default URL
- [ ] Tapping each button opens correct deep link
- [ ] App launches correctly

### Analytics
- [ ] `$opened_push` event tracked (body tap)
- [ ] `$opened_push_action` event tracked (button tap)
- [ ] Event contains `action_id` property
- [ ] Event contains `action_label` property (dynamic buttons only)

## Customization

To test with your own URLs, edit any JSON file and replace:
- `klaviyo://` with your app's URL scheme
- Button labels with your desired text
- Icons with SF Symbol names from [SF Symbols](https://developer.apple.com/sf-symbols/)

## Common SF Symbols for E-commerce

| Icon Name | Symbol | Use Case |
|-----------|--------|----------|
| `cart.fill` | 🛒 | Shopping, cart |
| `creditcard.fill` | 💳 | Checkout, payment |
| `shippingbox.fill` | 📦 | Shipping, delivery |
| `gift.fill` | 🎁 | Offers, promotions |
| `heart.fill` | ❤️ | Favorites, wishlist |
| `star.fill` | ⭐ | Featured items |
| `eye.fill` | 👁 | View, browse |
| `bell.fill` | 🔔 | Reminders, alerts |
| `message.fill` | 💬 | Support, chat |
| `tag.fill` | 🏷 | Deals, discounts |
| `bag.fill` | 👜 | Products, shop |

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
