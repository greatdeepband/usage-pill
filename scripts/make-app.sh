#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Claude Usage Pill.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeUsagePill "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/"
codesign --force -s - "$APP"
echo "Built: $APP"
