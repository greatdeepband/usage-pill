#!/bin/bash
# One-time: create a local self-signed code-signing identity. Ad-hoc signatures
# change every build, which resets the keychain "Always Allow" decision; a
# stable identity keeps it forever. Expect ONE macOS password prompt (trusting
# the new certificate) — that is the point of this script: it is the last one.
set -euo pipefail
CN="Claude Usage Pill Dev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CN"; then
    echo "Identity '$CN' already exists — nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$CN" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" -passout pass:cup-temp

# -T pre-authorizes codesign to use the private key without prompting.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P cup-temp -T /usr/bin/codesign

# Trust the cert for code signing (user trust domain) — triggers the one prompt.
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem"

echo "Created and trusted identity '$CN'. Rebuilds now keep keychain access."
