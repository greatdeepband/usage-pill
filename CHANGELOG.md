# Changelog

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
