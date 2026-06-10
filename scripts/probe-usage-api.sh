#!/bin/bash
# One-shot: verify the usage endpoint + credential shape. Prints the usage
# response (no secrets in it) and the credential JSON's KEY NAMES only.
set -euo pipefail
CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
        || cat "$HOME/.claude/.credentials.json")
echo "--- credential key structure (no values) ---"
echo "$CREDS" | /usr/bin/python3 -c '
import sys, json
def keys(o, p=""):
    if isinstance(o, dict):
        for k, v in o.items(): keys(v, f"{p}.{k}")
    else: print(f"{p}: {type(o).__name__}")
keys(json.load(sys.stdin))'
TOKEN=$(echo "$CREDS" | /usr/bin/python3 -c \
  'import sys,json; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')
echo "--- usage endpoint response ---"
curl -sS https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Content-Type: application/json" | /usr/bin/python3 -m json.tool
