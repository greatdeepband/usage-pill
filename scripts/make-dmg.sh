#!/bin/bash
# Package the already-built (signed + notarized) app into a drag-to-Applications
# disk image, then sign + notarize + staple the DMG itself so the download is
# Gatekeeper-clean at the image level too — not just the app inside it.
#
# Run scripts/make-app.sh FIRST (this packages build/Usage Pill.app as-is).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Usage Pill.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found — run scripts/make-app.sh first." >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)"
DMG="build/Usage-Pill-${VERSION}.dmg"
VOL="Usage Pill"
STAGE="build/dmg-stage"

# Stage the app beside a symlink to /Applications (the classic drag target).
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/Usage Pill.app"   # preserves the app's stapled ticket
ln -s /Applications "$STAGE/Applications"

# Compressed, read-only image.
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Created: $DMG"

# Sign the DMG with the same Developer ID the app uses.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
IDENTITY="${DEVELOPER_ID_IDENTITY:-$DEV_ID}"
if [ -z "$IDENTITY" ]; then
    echo "WARNING: no Developer ID found — DMG left unsigned/un-notarized." >&2
    echo "Built: $DMG"; exit 0
fi
codesign --force -s "$IDENTITY" "$DMG"
echo "Signed DMG with: $IDENTITY"

# Notarize + staple the DMG (set NOTARIZE=0 to skip).
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-usage-pill-notary}"
if [ "${NOTARIZE:-1}" = "1" ]; then
    echo "Notarizing DMG (a few minutes)…"
    set +e
    OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARIZE_PROFILE" --wait 2>&1)"
    set -e
    echo "$OUT"
    if ! grep -q "status: Accepted" <<<"$OUT"; then
        echo "ERROR: DMG notarization was not Accepted." >&2
        SUBID="$(grep -m1 -E '^[[:space:]]*id:' <<<"$OUT" | awk '{print $2}')"
        [ -n "$SUBID" ] && xcrun notarytool log "$SUBID" \
            --keychain-profile "$NOTARIZE_PROFILE" >&2 || true
        exit 1
    fi
    xcrun stapler staple "$DMG"
    echo "Stapled DMG."
fi
# Authoritative Gatekeeper verdict for a disk image.
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 || true
xcrun stapler validate "$DMG" 2>&1 | tail -1
echo "Built: $DMG"
