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

**Scenario**: Flash sale with Shop Now and Remind Later buttons

**File**: `test-payload-1-basic.json`

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
    "url": "klaviyo://home",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.shop",
        "label": "Shop Now",
        "url": "klaviyo://sale/flash"
      },
      {
        "id": "com.klaviyo.test.later",
        "label": "Remind Later",
        "url": "klaviyo://reminders"
      }
    ]
  }
}
```

**Expected Behavior**:
- 2 buttons appear: [Remind Later] [Shop Now] (reversed per iOS convention)
- Tapping "Shop Now" → opens `klaviyo://sale/flash`
- Tapping "Remind Later" → opens `klaviyo://reminders`
- Event `$opened_push_action` tracked with `action_id` and `action_label`

---

## Test Payload 2: With SF Symbols Icons (iOS 15+)

**Scenario**: Order shipped notification with icons

**File**: `test-payload-2-icons.json`

```json
{
  "aps": {
    "alert": {
      "title": "📦 Package Delivered",
      "body": "Your order #12345 was delivered today"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_order_delivered_002",
    "url": "klaviyo://orders/12345",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.track",
        "label": "View Details",
        "url": "klaviyo://orders/12345/tracking",
        "icon": "shippingbox.fill"
      },
      {
        "id": "com.klaviyo.test.support",
        "label": "Contact Support",
        "url": "klaviyo://support",
        "icon": "message.fill"
      }
    ]
  }
}
```

**Expected Behavior** (iOS 15+):
- 2 buttons with icons appear
- Icons display as SF Symbols
- On iOS <15: buttons appear without icons (graceful fallback)

---

## Test Payload 3: Three Buttons

**Scenario**: Product recommendation with 3 options

**File**: `test-payload-3-three-buttons.json`

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
    "url": "klaviyo://home",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.view",
        "label": "Browse All",
        "url": "klaviyo://new-arrivals",
        "icon": "eye.fill"
      },
      {
        "id": "com.klaviyo.test.favorites",
        "label": "Favorites",
        "url": "klaviyo://favorites",
        "icon": "heart.fill"
      },
      {
        "id": "com.klaviyo.test.dismiss",
        "label": "Not Now"
      }
    ]
  }
}
```

**Expected Behavior**:
- 3 buttons appear in original order (no reversal for 3+ buttons)
- "Not Now" button has no URL (dismisses notification)

---

## Test Payload 4: Single Button

**Scenario**: Simple call-to-action

**File**: `test-payload-4-single-button.json`

```json
{
  "aps": {
    "alert": {
      "title": "Don't Miss Out!",
      "body": "Your cart items are selling fast"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_single_button_004",
    "url": "klaviyo://cart",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.checkout",
        "label": "Complete Purchase",
        "url": "klaviyo://checkout",
        "icon": "creditcard.fill"
      }
    ]
  }
}
```

**Expected Behavior**:
- 1 button appears
- Tapping button opens checkout
- Tapping notification body opens cart

---

## Test Payload 5: Abandoned Cart Recovery

**Scenario**: E-commerce abandoned cart with compelling CTAs

**File**: `test-payload-5-abandoned-cart.json`

```json
{
  "aps": {
    "alert": {
      "title": "Your Cart is Waiting 🛒",
      "body": "Complete your purchase now and get free shipping!"
    },
    "mutable-content": 1,
    "sound": "default",
    "badge": 1
  },
  "body": {
    "_k": "test_abandoned_cart_005",
    "url": "klaviyo://cart",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.checkout",
        "label": "Checkout",
        "url": "klaviyo://checkout?source=push",
        "icon": "cart.fill"
      },
      {
        "id": "com.klaviyo.test.browse",
        "label": "Keep Shopping",
        "url": "klaviyo://shop",
        "icon": "square.grid.2x2.fill"
      }
    ]
  }
}
```

---

## Test Payload 6: Back in Stock Alert

**Scenario**: Product availability notification

**File**: `test-payload-6-back-in-stock.json`

```json
{
  "aps": {
    "alert": {
      "title": "Good News! 🎉",
      "body": "The Nike Air Max you wanted is back in stock"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_back_in_stock_006",
    "url": "klaviyo://product/nike-air-max-123",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.buy",
        "label": "Buy Now",
        "url": "klaviyo://product/nike-air-max-123/quick-buy",
        "icon": "cart.fill.badge.plus"
      },
      {
        "id": "com.klaviyo.test.view",
        "label": "View Product",
        "url": "klaviyo://product/nike-air-max-123",
        "icon": "eye.fill"
      }
    ]
  }
}
```

---

## Test Payload 7: Fallback to Predefined Category

**Scenario**: Test backwards compatibility with predefined categories

**File**: `test-payload-7-predefined-fallback.json`

```json
{
  "aps": {
    "alert": {
      "title": "Order Shipped",
      "body": "Your order is on its way"
    },
    "category": "com.klaviyo.category.viewDismiss",
    "sound": "default"
  },
  "body": {
    "_k": "test_predefined_007",
    "url": "klaviyo://orders/12345",
    "actions": {
      "com.klaviyo.action.view": {
        "url": "klaviyo://orders/12345/track"
      },
      "com.klaviyo.action.dismiss": {}
    }
  }
}
```

**Note**: This payload does NOT have `mutable-content: 1`, so it will use predefined categories if registered. Useful for testing fallback behavior.

---

## Test Payload 8: Hybrid (Both Dynamic and Predefined)

**Scenario**: Maximum compatibility - works with or without NSE

**File**: `test-payload-8-hybrid.json`

```json
{
  "aps": {
    "alert": {
      "title": "Special Offer Inside",
      "body": "Exclusive deal just for you"
    },
    "category": "com.klaviyo.category.viewDismiss",
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_hybrid_008",
    "url": "klaviyo://offers",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.claim",
        "label": "Claim Offer",
        "url": "klaviyo://offers/claim",
        "icon": "gift.fill"
      },
      {
        "id": "com.klaviyo.test.dismiss",
        "label": "No Thanks"
      }
    ],
    "actions": {
      "com.klaviyo.action.view": {
        "url": "klaviyo://offers"
      },
      "com.klaviyo.action.dismiss": {}
    }
  }
}
```

**Expected Behavior**:
- With NSE: Uses dynamic buttons ("Claim Offer" / "No Thanks")
- Without NSE: Uses predefined buttons ("View" / "Dismiss")

---

## Test Payload 9: Localization Test

**Scenario**: Spanish language buttons

**File**: `test-payload-9-spanish.json`

```json
{
  "aps": {
    "alert": {
      "title": "¡Venta Relámpago!",
      "body": "50% de descuento en todo"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": "test_localization_009",
    "url": "klaviyo://home",
    "action_buttons": [
      {
        "id": "com.klaviyo.test.shop",
        "label": "Comprar Ahora",
        "url": "klaviyo://sale",
        "icon": "cart.fill"
      },
      {
        "id": "com.klaviyo.test.later",
        "label": "Recordar Después",
        "url": "klaviyo://reminders"
      }
    ]
  }
}
```

**Purpose**: Demonstrates server-side localization of button labels

---

## Test Payload 10: Error Cases

**Scenario**: Invalid payload to test error handling

**File**: `test-payload-10-invalid.json`

```json
{
  "aps": {
    "alert": "Missing mutable-content",
    "sound": "default"
  },
  "body": {
    "_k": "test_invalid_010",
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

# Test payload number
PAYLOAD_NUM=${1:-1}

# Send notification
cd /Users/ajay.subramanya/Klaviyo/Repos/apns-cli

apns-cli send \
  --token "$DEVICE_TOKEN" \
  --bundle-id "$BUNDLE_ID" \
  --team-id "$TEAM_ID" \
  --key-id "$KEY_ID" \
  --key-path "$KEY_PATH" \
  --payload "test-payload-${PAYLOAD_NUM}.json"

echo "Sent test payload #${PAYLOAD_NUM}"
```

**Usage**:
```bash
chmod +x test-push.sh
./test-push.sh 1  # Send payload 1
./test-push.sh 2  # Send payload 2
```

---

## Verification Checklist

After sending a test payload, verify:

### Visual Verification
- [ ] Notification appears in notification center
- [ ] Long-press or swipe shows action buttons
- [ ] Button labels are correct
- [ ] Icons appear (iOS 15+) or gracefully absent
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
- [ ] Test on iOS 14 with icons → fallback to no icons
- [ ] Test with invalid payload → notification still displays
- [ ] Test with 128+ notifications → category pruning works

---

## Common SF Symbols for E-commerce

Use these icon names in the `icon` field:

| Icon Name | Symbol | Use Case |
|-----------|--------|----------|
| `cart.fill` | 🛒 | Shopping, Add to cart |
| `cart.fill.badge.plus` | 🛒+ | Add item |
| `creditcard.fill` | 💳 | Checkout, Payment |
| `shippingbox.fill` | 📦 | Shipping, Delivery |
| `gift.fill` | 🎁 | Offers, Promotions |
| `heart.fill` | ❤️ | Favorites, Wishlist |
| `star.fill` | ⭐ | Featured, Popular |
| `eye.fill` | 👁 | View, Browse |
| `bell.fill` | 🔔 | Reminders, Alerts |
| `message.fill` | 💬 | Support, Chat |
| `tag.fill` | 🏷 | Deals, Discounts |
| `percent` | % | Sale, Discount |
| `bag.fill` | 👜 | Products, Shop |
| `square.grid.2x2.fill` | ▦ | Browse, Catalog |

**Find More**: [SF Symbols Browser](https://developer.apple.com/sf-symbols/)

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
