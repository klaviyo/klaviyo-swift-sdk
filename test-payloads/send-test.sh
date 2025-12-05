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
