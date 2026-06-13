#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="FreeMic.app"

# Build both architectures separately and lipo them into one universal binary.
# (A single `swift build --arch arm64 --arch x86_64` needs full Xcode; building
#  each arch with the native toolchain + lipo works with Command Line Tools only.)
echo "▶︎ Building arm64 (release)…"
swift build -c release
ARM_BIN="$(swift build -c release --show-bin-path)/FreeMic"

echo "▶︎ Building x86_64 (release, cross-compile)…"
swift build -c release --triple x86_64-apple-macosx13.0
X86_BIN="$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/FreeMic"

echo "▶︎ Assembling ${APP} (universal)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/FreeMic"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶︎ Ad-hoc codesigning…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Distribution (Developer ID + notarization) — requires an Apple Developer
# account ($99/yr). Without this, other users must manually allow the app on
# first launch (right-click → Open, or `xattr -dr com.apple.quarantine`).
# To enable, set DEVELOPER_ID + NOTARY_PROFILE and run with NOTARIZE=1:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="freemic-notary"   # stored via `xcrun notarytool store-credentials`
#   codesign --force --options runtime --timestamp \
#            --sign "$DEVELOPER_ID" "$APP"
#   ditto -c -k --keepParent "$APP" FreeMic.zip
#   xcrun notarytool submit FreeMic.zip --keychain-profile "$NOTARY_PROFILE" --wait
#   xcrun stapler staple "$APP"
# ---------------------------------------------------------------------------

echo "✅ Done: ${APP}  ($(lipo -archs "$APP/Contents/MacOS/FreeMic"))"
echo "   启动:   open ${APP}"
echo "   调试:   ${APP}/Contents/MacOS/FreeMic --list"
