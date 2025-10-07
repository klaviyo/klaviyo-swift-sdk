#!/bin/bash

# Watch Klaviyo Forms logs in real-time
# Usage: ./watch-logs.sh

echo "📱 Watching Klaviyo Forms logs..."
echo "🔴 Kill your app, send push, tap notification, and watch here!"
echo "---"

log stream --predicate 'subsystem CONTAINS "klaviyo"' --level debug --style compact
