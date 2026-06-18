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

# === Signing identity ===
# Prefer a real Apple Developer ID: it is notarizable, Gatekeeper-clean, and —
# crucially — gives a STABLE teamid:-keyed keychain partition. That means our
# OWN provider-key items (service pl.bbi.usage-pill.providers) are read silently
# across every rebuild/update, instead of re-prompting on each new cdhash the
# way a self-signed cert does. We fall back to the stable local dev cert only
# when no Developer ID is present.
#
# We REFUSE ad-hoc signing: an ad-hoc build's designated requirement is
# cdhash-based, so it changes every build, invalidating keychain ACL grants and
# reviving the password-prompt-on-every-launch bug. Fail loudly instead.
#
# DO NOT enable App Sandbox (com.apple.security.app-sandbox): it would block BOTH
# the /usr/bin/security subprocess (used to read Claude's credential prompt-free)
# AND cross-app keychain access. Hardened runtime (--options runtime, required
# for notarization) is fine — it does NOT block the subprocess; only App Sandbox
# does. This app therefore ships via Developer ID + notarization, NOT the Mac App
# Store (which mandates the sandbox).
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
IDENTITY="${DEVELOPER_ID_IDENTITY:-${DEV_ID:-Claude Usage Pill Dev}}"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
    echo "ERROR: code-signing identity \"$IDENTITY\" not found." >&2
    echo "       Run scripts/make-signing-cert.sh once to create the stable dev cert," >&2
    echo "       or export DEVELOPER_ID_IDENTITY=\"Developer ID Application: …\"." >&2
    echo "       NOT falling back to ad-hoc — that would re-break keychain trust." >&2
    exit 1
fi

# Hardened runtime + a secure timestamp are required for notarization, and are
# only meaningful when signing with a Developer ID. The dev cert can't be
# notarized, so it signs without them.
SIGN_OPTS=(--force -s "$IDENTITY")
IS_DEVELOPER_ID=0
case "$IDENTITY" in
    "Developer ID Application: "*)
        IS_DEVELOPER_ID=1
        SIGN_OPTS+=(--options runtime --timestamp)
        ;;
esac
codesign "${SIGN_OPTS[@]}" "$APP"
echo "Signed with: $IDENTITY"
# A corrupt signature also forces the keychain to re-prompt — verify it satisfies
# its own designated requirement before we go further.
codesign --verify --deep --strict "$APP"
echo "Signature verified."

# === Notarization + stapling (Developer ID only) ===
# Set NOTARIZE=0 to skip (e.g. a fast local rebuild). Default: notarize whenever
# we signed with a Developer ID. Needs the stored notary profile (create once:
#   xcrun notarytool store-credentials "$NOTARIZE_PROFILE" \
#       --apple-id <id> --team-id <team> --password <app-specific-pw> ).
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-usage-pill-notary}"
ZIP="build/Usage Pill.zip"
if [ "$IS_DEVELOPER_ID" = "1" ] && [ "${NOTARIZE:-1}" = "1" ]; then
    rm -f "$ZIP"
    # ditto --keepParent preserves the .app wrapper the notary service expects.
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Submitting to Apple notary service (this can take a few minutes)…"
    set +e
    SUBMIT_OUT="$(xcrun notarytool submit "$ZIP" \
        --keychain-profile "$NOTARIZE_PROFILE" --wait 2>&1)"
    set -e
    echo "$SUBMIT_OUT"
    if ! grep -q "status: Accepted" <<<"$SUBMIT_OUT"; then
        echo "ERROR: notarization was not Accepted — see the log below." >&2
        SUBID="$(grep -m1 -E '^[[:space:]]*id:' <<<"$SUBMIT_OUT" | awk '{print $2}')"
        [ -n "$SUBID" ] && xcrun notarytool log "$SUBID" \
            --keychain-profile "$NOTARIZE_PROFILE" >&2 || true
        exit 1
    fi
    # Staple the ticket INTO the bundle so Gatekeeper passes offline / on first
    # launch with no network round-trip.
    xcrun stapler staple "$APP"
    echo "Stapled."
    # Re-zip the now-stapled bundle for distribution.
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Distribution zip: $ZIP"
    # Final, authoritative Gatekeeper verdict (should say: accepted, Notarized
    # Developer ID).
    spctl -a -vvv --type execute "$APP" || true
elif [ "$IS_DEVELOPER_ID" = "1" ]; then
    echo "NOTARIZE=0 — skipping notarization/stapling."
fi
echo "Built: $APP"
