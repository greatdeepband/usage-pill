#!/bin/bash
# One-time: create a local self-signed code-signing identity. Ad-hoc signatures
# change every build, which resets the keychain "Always Allow" decision; a
# stable identity keeps it forever.
#
# Expect exactly TWO prompts — then silence, including across all future rebuilds:
#   1. A macOS password/trust prompt when this script calls add-trusted-cert.
#   2. A keychain "Always Allow" prompt the very first time the newly-signed app
#      reads the Claude Code credentials from your keychain.
# After those two, no further prompts — even when you rebuild the app.
set -euo pipefail
CN="Claude Usage Pill Dev"

# --- Untrusted-leftover cleanup ---
# A previous interrupted run may have imported the cert without trusting it.
# Such a leftover is invisible to find-identity but blocks reimport; remove it.
if security find-certificate -c "$CN" >/dev/null 2>&1 && \
   ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$CN\""; then
    echo "Found an untrusted leftover '$CN' — removing it first."
    security delete-certificate -c "$CN" "$HOME/Library/Keychains/login.keychain-db"
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$CN\""; then
    echo "Identity '$CN' already exists — nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$CN" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Legacy PBE/MAC algorithms: OpenSSL 3 defaults (AES + SHA-256 MAC) are not
# readable by macOS `security import`.
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" -passout pass:cup-temp \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

# -T pre-authorizes codesign to use the private key without prompting.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P cup-temp -T /usr/bin/codesign

# Trust the cert for code signing (user trust domain) — triggers the one prompt.
# If the trust prompt is canceled, delete the just-imported certificate so nothing
# is left in a broken half-trusted state, then exit with a clear message.
if ! security add-trusted-cert -r trustRoot -p codeSign \
       -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem"; then
    security delete-certificate -c "$CN" "$HOME/Library/Keychains/login.keychain-db"
    echo "Trust prompt was canceled — the certificate has been removed. Nothing was left behind."
    echo "Re-run this script when you are ready to trust the identity."
    exit 1
fi

echo "Created and trusted identity '$CN'."
echo "You will see one more 'Always Allow' prompt the first time the app reads your Claude Code credentials — after that, silence across all future rebuilds."
