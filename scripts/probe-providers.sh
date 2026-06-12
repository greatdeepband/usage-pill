#!/bin/bash
# One-shot: verify provider endpoint shapes for v2.0 presets.
# Usage: DEEPSEEK_KEY=sk-... OPENROUTER_KEY=... ./scripts/probe-providers.sh
# Sections are skipped when their env var is unset. Keys go to curl via
# --config stdin (never argv) and are never printed.
set -uo pipefail

probe() { # name url key [extra curl args...]
  local name="$1" url="$2" key="$3"; shift 3
  echo "=== $name ==="
  if [ -z "$key" ]; then echo "(skipped — no key provided)"; return; fi
  printf 'header = "Authorization: Bearer %s"\n' "$key" | \
    curl -sS --max-time 15 --config - "$url" "$@" | /usr/bin/python3 -m json.tool || echo "(request failed)"
}

probe "DeepSeek balance"   "https://api.deepseek.com/user/balance" "${DEEPSEEK_KEY:-}"
probe "OpenRouter credits" "https://openrouter.ai/api/v1/credits"  "${OPENROUTER_KEY:-}"
probe "MiniMax balance"    "https://api.minimax.io/v1/user/balance" "${MINIMAX_KEY:-}"
