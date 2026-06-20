#!/bin/bash
# Builds the Mac App Store (sandboxed, providers-only) variant of Usage Pill.
#
# The MAS variant compiles out the Claude-plan credential path (App Sandbox
# cannot read Claude Code's keychain item) and keeps every provider-balance
# feature, which works fine sandboxed. All MAS-specific behaviour is gated
# behind the -DMAS_BUILD compile flag, so the Developer-ID make-app.sh build is
# completely untouched. See docs/APPSTORE.md for the full submission runbook.
#
# Usage: scripts/make-appstore.sh [proof|dist]   (default: proof)
#   proof — runnable locally, NO distribution certs needed. Signs with the
#           Developer ID identity + sandbox entitlements + hardened runtime so
#           we can launch it and prove the sandbox + providers actually work.
#   dist  — produces the App Store .pkg. Requires the distribution identities +
#           a provisioning profile (env vars below); fails loudly if absent.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-proof}"
APP="build/Usage Pill (MAS).app"
ENTITLEMENTS="scripts/appstore.entitlements"

# === Guard: the MAS build must never compile in the Claude credential path ===
# App Sandbox cannot read Claude Code's keychain item, so a reachable
# construction of the credential reader/fetcher would be a security regression.
# This static, #if-aware check fails the build before signing if one slips in.
python3 scripts/check-mas-isolation.py

# === Common: build (-DMAS_BUILD) + assemble the bundle ===
swift build -c release -Xswiftc -DMAS_BUILD
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeUsagePill "$APP/Contents/MacOS/ClaudeUsagePill"
cp scripts/Info-appstore.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/"

case "$MODE" in
proof)
    # === proof mode: Developer ID + sandbox, runnable locally ===
    # Auto-detect a Developer ID Application identity. App Sandbox is what the
    # App Store mandates; signing with Developer ID + the sandbox entitlements
    # + hardened runtime lets us LAUNCH the exact sandboxed binary locally and
    # confirm providers work and no Claude path exists — without needing the
    # distribution certs that can only be minted through Apple's web UI.
    DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
    if [ -z "$DEV_ID" ]; then
        echo "ERROR: no 'Developer ID Application' identity found in the keychain." >&2
        echo "       proof mode signs with Developer ID + the sandbox entitlements" >&2
        echo "       so the sandboxed build can run locally. See docs/APPSTORE.md." >&2
        exit 1
    fi
    codesign --force --sign "$DEV_ID" \
        --entitlements "$ENTITLEMENTS" --options runtime --timestamp "$APP"
    echo "Signed with: $DEV_ID"
    echo
    echo "=== codesign --verify --strict --verbose=2 ==="
    codesign --verify --strict --verbose=2 "$APP"
    echo
    echo "=== codesign -d --entitlements :- (must show com.apple.security.app-sandbox) ==="
    codesign -d --entitlements :- "$APP"
    echo
    echo "Proof build ready: $APP"
    ;;
dist)
    # === dist mode: Apple Distribution + installer signing → App Store .pkg ===
    # Requires the two distribution identities + a provisioning profile, all of
    # which must be created through Apple's web UI / Xcode (see docs/APPSTORE.md).
    # We fail loudly rather than falling back — a wrong signature is rejected by
    # App Store Connect anyway.
    MISSING=0
    [ -n "${MAS_APP_IDENTITY:-}" ]       || { echo "ERROR: MAS_APP_IDENTITY is not set." >&2; MISSING=1; }
    [ -n "${MAS_INSTALLER_IDENTITY:-}" ] || { echo "ERROR: MAS_INSTALLER_IDENTITY is not set." >&2; MISSING=1; }
    [ -n "${MAS_PROFILE:-}" ]            || { echo "ERROR: MAS_PROFILE (path to a .provisionprofile) is not set." >&2; MISSING=1; }
    if [ "$MISSING" = "1" ]; then
        echo "       dist mode needs all three. See docs/APPSTORE.md for how to create them." >&2
        exit 1
    fi
    if [ ! -f "$MAS_PROFILE" ]; then
        echo "ERROR: MAS_PROFILE file not found: $MAS_PROFILE" >&2
        echo "       See docs/APPSTORE.md." >&2
        exit 1
    fi
    if ! security find-identity -v 2>/dev/null | grep -qF "$MAS_APP_IDENTITY"; then
        echo "ERROR: signing identity not in the keychain: $MAS_APP_IDENTITY" >&2
        echo "       Create the Apple Distribution certificate first (docs/APPSTORE.md)." >&2
        exit 1
    fi
    if ! security find-identity -v 2>/dev/null | grep -qF "$MAS_INSTALLER_IDENTITY"; then
        echo "ERROR: installer identity not in the keychain: $MAS_INSTALLER_IDENTITY" >&2
        echo "       Create the Mac Installer Distribution certificate first (docs/APPSTORE.md)." >&2
        exit 1
    fi

    # Embed the provisioning profile BEFORE signing — the signature must cover it.
    cp "$MAS_PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign --force --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$MAS_APP_IDENTITY" "$APP"
    echo "Signed with: $MAS_APP_IDENTITY"
    PKG="build/Usage-Pill-MAS.pkg"
    rm -f "$PKG"
    productbuild --component "$APP" /Applications \
        --sign "$MAS_INSTALLER_IDENTITY" "$PKG"
    echo "Built App Store package: $PKG"

    # Upload command for reference (fill in the bracketed values; the app
    # record id is the numeric Apple ID of the App Store Connect app record):
    : <<'UPLOAD'
xcrun altool --upload-package "build/Usage-Pill-MAS.pkg" --type macos \
    -u "<apple-id>" -p "<app-specific-password>" \
    --apple-id "<numeric-app-record-id>" \
    --bundle-id pl.bbi.usage-pill \
    --bundle-version 1 --bundle-short-version-string 1.0.0
UPLOAD
    ;;
*)
    echo "ERROR: unknown mode '$MODE'. Use: proof | dist" >&2
    exit 1
    ;;
esac
