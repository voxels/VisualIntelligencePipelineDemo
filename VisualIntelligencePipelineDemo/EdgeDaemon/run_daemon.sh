#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Change to the script's directory (EdgeDaemon root)
cd "$(dirname "$0")"

echo "⚙️  Building EdgeDaemon..."
xcodebuild -project EdgeDaemon.xcodeproj -scheme EdgeDaemon -destination 'platform=macOS' build -quiet

# Get the path to the compiled app
EXECUTABLE_PATH=$(xcodebuild -project EdgeDaemon.xcodeproj -scheme EdgeDaemon -destination 'platform=macOS' -showBuildSettings | grep -m 1 "CODESIGNING_FOLDER_PATH" | awk -F'= ' '{print $2}')

echo "🚀 Launching EdgeDaemon from Terminal..."
echo "ℹ️  Note: Terminal execution bypasses macOS Local Network Privacy restrictions on ad-hoc signed apps."
echo ""

# Kill any existing instance
killall EdgeDaemon 2>/dev/null || true

# Run the daemon
"$EXECUTABLE_PATH"
