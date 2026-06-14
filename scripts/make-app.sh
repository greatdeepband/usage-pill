#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Usage Pill.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeUsagePill "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/"
cp scripts/AppIcon.icns "$APP/Contents/Resources/"
# Sign with the stable local identity (scripts/make-signing-cert.sh) so the
# keychain "Always Allow" decision survives rebuilds. We REFUSE to fall back to
# ad-hoc signing: an ad-hoc build's designated requirement is cdhash-based, so
# it changes every build, invalidating the keychain ACL grant and reviving the
# password-prompt-on-every-launch bug. Fail loudly instead.
#
# To sign with a real Apple Developer ID instead (notarizable, Gatekeeper-clean,
# the most robust option), set DEVELOPER_ID_IDENTITY to your
# "Developer ID Application: …" identity before running.
IDENTITY="${DEVELOPER_ID_IDENTITY:-Claude Usage Pill Dev}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
    echo "ERROR: code-signing identity \"$IDENTITY\" not found." >&2
    echo "       Run scripts/make-signing-cert.sh once to create the stable dev cert," >&2
    echo "       or export DEVELOPER_ID_IDENTITY=\"Developer ID Application: …\"." >&2
    echo "       NOT falling back to ad-hoc — that would re-break keychain trust." >&2
    exit 1
fi
# Note: when you move to Developer ID + notarization, add `--options runtime`
# here (hardened runtime is required for notarization).
codesign --force -s "$IDENTITY" "$APP"
echo "Signed with: $IDENTITY"
# Verify the signature is valid and satisfies its own designated requirement —
# a corrupt signature also forces the keychain to re-prompt.
codesign --verify --deep --strict "$APP"
echo "Signature verified."
echo "Built: $APP"
