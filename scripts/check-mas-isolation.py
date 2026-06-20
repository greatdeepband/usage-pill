#!/usr/bin/env python3
"""Fail the MAS build if the Claude credential path could compile into it.

Scans the app target (Sources/ClaudeUsagePill) and asserts that NO construction
of a Claude-credential type appears in code that is ACTIVE when MAS_BUILD is
defined. The sandboxed Mac App Store build must never instantiate these — see
docs/superpowers/specs/2026-06-21-appstore-sandbox-variant-design.md.

It is `#if`-aware (MAS_BUILD / !MAS_BUILD / #else / #endif) and strips comments
and string literals, so plain TYPE references (`UsageModel?`) and doc comments
that merely name these types are NOT flagged — only real construction calls
(token immediately followed by `(`).
"""
import os
import sys

APP_DIR = os.path.join(os.path.dirname(__file__), "..", "Sources", "ClaudeUsagePill")

# Construction call sites that must never be reachable in the MAS build.
FORBIDDEN = [
    "KeychainCredentialsProvider(",
    "SecurityToolReader(",
    "CredentialsCache(",
    "ProfileFetcher(",
    "UsageFetcher(",
    "UsageModel(",
    "IdentityModel(",
]


def strip_comments(line, in_block):
    """Remove /* */ and // comments, respecting string literals (so "https://"
    survives). Returns (code, in_block_after)."""
    out = []
    i, n = 0, len(line)
    in_str = False
    while i < n:
        two = line[i:i + 2]
        if in_block:
            if two == "*/":
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            out.append(line[i])
            if line[i] == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = False
            i += 1
            continue
        if two == "//":
            break
        if two == "/*":
            in_block = True
            i += 2
            continue
        if line[i] == '"':
            in_str = True
            out.append('"')
            i += 1
            continue
        out.append(line[i])
        i += 1
    return "".join(out), in_block


def scan(path):
    """Return [(lineno, token, code)] for forbidden constructions reachable
    when MAS_BUILD is defined."""
    violations = []
    active = []   # active-under-MAS bool per enclosing #if frame
    is_mas = []   # whether each frame is a MAS_BUILD condition
    in_block = False
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            s = raw.strip()
            if s.startswith("#if"):
                cond = s[3:].strip()
                if cond == "MAS_BUILD":
                    active.append(True); is_mas.append(True)
                elif cond == "!MAS_BUILD":
                    active.append(False); is_mas.append(True)
                else:
                    active.append(True); is_mas.append(False)  # unrelated → conservative
                continue
            if s.startswith("#elseif"):
                # Rare; treat conservatively as active for non-MAS conditions.
                if active and is_mas[-1]:
                    active[-1] = False  # we can't know; stay safe by not re-activating MAS code
                continue
            if s.startswith("#else"):
                if active and is_mas[-1]:
                    active[-1] = not active[-1]
                continue
            if s.startswith("#endif"):
                if active:
                    active.pop(); is_mas.pop()
                continue
            code, in_block = strip_comments(raw, in_block)
            if all(active):  # all([]) is True → top level is active
                for tok in FORBIDDEN:
                    if tok in code:
                        violations.append((lineno, tok, code.strip()))
    return violations


def main():
    total = 0
    for name in sorted(os.listdir(APP_DIR)):
        if not name.endswith(".swift"):
            continue
        for lineno, tok, code in scan(os.path.join(APP_DIR, name)):
            total += 1
            print(f"  LEAK: {name}:{lineno} constructs `{tok}` in MAS-active code: {code}",
                  file=sys.stderr)
    if total:
        print(f"check-mas-isolation: FAIL — {total} Claude-credential construction(s) "
              f"reachable in the MAS build.", file=sys.stderr)
        sys.exit(1)
    print("check-mas-isolation: OK — no Claude-credential construction is reachable "
          "when MAS_BUILD is defined.")


if __name__ == "__main__":
    main()
