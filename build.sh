#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="FreeMic.app"
BIN=".build/release/FreeMic"

echo "▶︎ Building (release)…"
swift build -c release

echo "▶︎ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FreeMic"
cp Info.plist "$APP/Contents/Info.plist"

echo "▶︎ Ad-hoc codesigning…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ Done: ${APP}"
echo "   启动:   open ${APP}"
echo "   调试:   ${BIN} --list"
