#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Claude Usage Pill.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeUsagePill "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/"
# Prefer the stable local identity (scripts/make-signing-cert.sh) so the
# keychain "Always Allow" decision survives rebuilds; fall back to ad-hoc.
IDENTITY="Claude Usage Pill Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force -s "$IDENTITY" "$APP"
    echo "Signed with stable identity: $IDENTITY"
else
    codesign --force -s - "$APP"
    echo "Signed ad-hoc — run scripts/make-signing-cert.sh once for a stable identity"
fi
echo "Built: $APP"
