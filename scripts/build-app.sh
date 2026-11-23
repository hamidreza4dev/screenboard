#!/usr/bin/env bash
# Builds ScreenBoard.app into ./build. Set SIGN_IDENTITY to a Developer ID
# identity for a stable signature (ad-hoc signing makes macOS forget the
# Accessibility grant on every rebuild).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
# Universal binary (Apple silicon + Intel) by default.
ARCH_FLAGS=(--arch arm64 --arch x86_64)
[ -n "${ARCHS:-}" ] && { ARCH_FLAGS=(); for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done; }
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/ScreenBoard"
APP="build/ScreenBoard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenBoard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
