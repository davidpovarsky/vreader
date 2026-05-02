#!/usr/bin/env bash
# Purpose: Acceptance gate for feature #44 — verify the DebugBridge has zero
# release surface. Run after a Release build; exits 0 only if neither the
# vreader-debug URL scheme nor any DebugBridge symbol/string leaks into the
# shipped binary or Info.plist.
#
# Usage:
#   scripts/verify-release-no-debugbridge.sh [path/to/vreader.app]
#
# If no path is given, falls back to a default DerivedData location used by
# the local Release build invocation in dev-docs/debug-bridge.md.

set -euo pipefail

APP_PATH="${1:-/tmp/vreader-release-build/Build/Products/Release-iphonesimulator/vreader.app}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "FAIL: app bundle not found at $APP_PATH" >&2
    echo "Build first: xcodebuild build -configuration Release -derivedDataPath /tmp/vreader-release-build" >&2
    exit 2
fi

INFO_PLIST="$APP_PATH/Info.plist"
BIN_PATH="$APP_PATH/vreader"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "FAIL: Info.plist missing inside $APP_PATH" >&2
    exit 2
fi

if [[ ! -f "$BIN_PATH" ]]; then
    echo "FAIL: binary missing inside $APP_PATH" >&2
    exit 2
fi

FAIL=0

# 1. Info.plist must not declare the vreader-debug URL scheme
if plutil -p "$INFO_PLIST" | grep -q "vreader-debug"; then
    echo "FAIL: Info.plist contains vreader-debug URL scheme" >&2
    FAIL=1
else
    echo "OK: Info.plist has no vreader-debug entry"
fi

# 2. Binary must not contain DebugBridge-related strings
LEAKED=$(strings "$BIN_PATH" | grep -ciE "vreader-debug|DebugBridge|DebugCommand|DebugFixtureCatalog|DebugSnapshot|LoggingDebugBridgeContext" || true)
if [[ "$LEAKED" -gt 0 ]]; then
    echo "FAIL: Release binary contains $LEAKED DebugBridge-related strings:" >&2
    strings "$BIN_PATH" | grep -iE "vreader-debug|DebugBridge|DebugCommand|DebugFixtureCatalog|DebugSnapshot|LoggingDebugBridgeContext" | head -5 >&2
    FAIL=1
else
    echo "OK: Release binary has no DebugBridge strings"
fi

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

echo "PASS: zero DebugBridge surface in Release build"
