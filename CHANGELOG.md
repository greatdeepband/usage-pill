# Changelog

## v1.2.0 — 2026-06-14

No more keychain password prompts. Claude Code rotates its OAuth token about
once an hour, and each rotation resets the macOS keychain item's access list —
silently revoking the "Always Allow" you granted, so the password prompt kept
coming back on every wake. That's Claude Code's behavior and can't be fixed
from our side (a paid Apple Developer certificate wouldn't change it either).

The fix: Claude can now connect with a **long-lived token** instead. In
Settings → Claude → Connection, choose "Use a token", run `claude setup-token`
in Terminal, and paste the result. Usage Pill stores it in its own keychain
item (silent, prompt-free, untouched by Claude Code's rotations). The
zero-setup auto-detect remains the default for anyone who doesn't mind the
occasional prompt.

## v1.1.0 — 2026-06-13

The catalog release: Add Provider now opens a grouped template catalog —
Plans (Claude, z.ai GLM 5-hour & weekly, MiniMax token plan) and API
balances & spend (DeepSeek, OpenRouter with true remaining credits,
MiniMax balance, OpenAI month-to-date spend). Every entry pre-fills what's
known, links to the provider's key page, and is live-verified when you add
it. Claude itself joined the catalog: fresh installs detect your Claude
Code sign-in automatically, and a guided walkthrough covers the rest.
OpenAI spend rows use warn-ABOVE thresholds and skip the drain bar (spend
grows). Existing setups upgrade with zero changes.

## v1.0.0 — 2026-06-13

First public release of Usage Pill — an always-on-top macOS widget showing
all your AI usage meters in one pill: Claude plan windows (session + week)
plus any number of API credit balances (DeepSeek preset included; add any
GET-JSON provider via the guided custom flow — paste URL + key, tap the
number you recognize). Per-provider colors, warn thresholds, drain bars
with per-launch baselines, red alert at 90% weekly, native-feel settings.

Usage Pill grew out of Claude Usage Pill; that project's full history is
preserved in this repository (the entries below predate the rename).

## v1.2.4 — 2026-06-12

- **App icon.** The widget now wears its own blue-pill icon in Finder,
  Launchpad, Spotlight, login items, and permission dialogs — no more
  generic placeholder.

## v1.2.3 — 2026-06-12

- **Self-healing credential cache.** The in-memory token previously refreshed
  only after a 401 — but a long-stale token can draw 429s instead (observed:
  the app sat unauthorized for 2 hours, then the server began throttling that
  token, and the reload path never fired again until a manual restart). The
  cache now silently re-reads the keychain every 30 minutes regardless of
  error pattern, and within 1 minute whenever its cached token is past its
  own expiry stamp — so the widget always converges on Claude Code's current
  token without prompts or restarts.

## v1.2.2 — 2026-06-11

- **Calmer polling.** The usage endpoint turned out to tolerate roughly one
  request per 2 minutes sustained; the previous 60-second poll drew alternating
  429s, leaving the pill in its "rate limited" state half the time. Polling is
  now every 3 minutes (the bars move slowly anyway), and the post-429 backoff
  floor rose to 4 minutes so a retry can't land straight back inside the
  throttling window. Refresh Now still fetches immediately.

## v1.2.1 — 2026-06-11

- **Plan badge now shows server truth.** The badge previously derived its
  multiplier from the locally stored credential metadata, which can lag a
  plan change (observed: "MAX 5×" shown for a Max 20× account). It now
  prefers `organization.rate_limit_tier` from the profile response and only
  falls back to the local copy when offline.

## v1.2 — 2026-06-11

Themes, identity display, and rate-limit resilience.

- **Settings window** (menu bar → Settings…): live preview, three palette
  presets — Dusk (default), Mist, Sage — plus native color wells for fully
  custom session/week bar colors. Changes apply instantly and persist.
  Warning amber (≥80%) and critical red (≥95%) remain fixed by design.
- **Account & plan display (optional, default off):** the hover-expanded card
  can show your account email and plan badge (e.g. "MAX 5×") in a header
  strip. The compact pill never shows it; the email lives in memory only —
  never written to disk, never logged, fetched only while the toggle is on.
- **Rate-limit resilience:** HTTP 429 now triggers a polite backoff
  (Retry-After-aware, 2–60 min) with a "rate limited — retrying later"
  footer note; Refresh Now deliberately overrides the backoff.
- **Single-instance guard:** launching a second copy defers to the running
  one (deterministic launch-date tiebreak), preventing accidental
  poll-storms from multiple instances.
- Credentials continue to flow through the one shared in-memory cache — no
  new keychain prompts for any of the above.

## v1.1 — 2026-06-11

Fixes the password-prompt storm reported after v1.0 rebuilds.

- **Credentials are cached in memory.** The keychain is read once per launch
  and again only when the API reports the token rotated (HTTP 401) — down from
  one read per 60-second poll. Failed loads are negative-cached, so even a
  denied keychain prompt cannot recur more than once per 10 minutes.
- **Only a true 401 triggers a credential reload.** A 403 (scope/policy
  refusal) no longer pokes the keychain.
- **Expired file-fallback tokens are skipped.** A stale
  `~/.claude/.credentials.json` previously caused a silent endless 401 loop
  with no data; it now surfaces the "open Claude Code to sign in" state.
- **Stable code-signing identity.** `scripts/make-signing-cert.sh` (one-time)
  creates a local trusted identity; `make-app.sh` uses it automatically, so
  the keychain "Always Allow" decision survives rebuilds. Two prompts ever:
  one to trust the certificate, one Always Allow — then silence.
- Dropped a `nonisolated(unsafe)` made unnecessary by the current SDK.

## v1.0 — 2026-06-11

Initial release.

- Always-on-top floating pill: 5-hour session bar (clay) + weekly bar (dusty
  blue), Dusk palette, glass blur; hover expands to reset countdowns and a
  freshness footer; amber ≥80%, soft red ≥95% utilization.
- Visible on every Space and over full-screen apps; draggable with persisted,
  display-reconfiguration-safe position.
- Live data from the official usage endpoint via the Claude Code OAuth token
  (strictly read-only keychain access); 60 s polling plus wake-from-sleep and
  manual refresh; offline shows last data with an amber "updated…" note.
- Menu-bar gauge icon: Refresh Now, Launch at Login (from /Applications), Quit.
- Hardened by four adversarial review rounds: defensive JSON decoding
  (microsecond timestamps, insane epochs, boolean traps), URLError(.cancelled)
  normalization, bottom-edge expansion clamp, protected position persistence.
- 54 unit tests (decoding, credentials, fetcher, state machine, formatting,
  geometry); no third-party dependencies.
