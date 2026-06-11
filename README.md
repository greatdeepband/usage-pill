# Claude Usage Pill

A tiny always-on-top macOS widget showing your Claude usage as two slim bars:
the **5-hour session** window (clay) and the **weekly** limit (dusty blue).
Hover to expand it into a card with reset countdowns and data freshness.

- Floats above every window, on every Space, including over full-screen apps.
- Reads the exact percentages the `/usage` command reports, via the official
  endpoint, using your existing Claude Code login. **Strictly read-only**: it
  never writes to the keychain and never refreshes tokens (Claude Code owns
  that). If the token expires, the pill dims and recovers automatically the
  next time Claude Code refreshes it.
- Refreshes every 60 s, on wake from sleep, and on demand from the menu bar.
- Drag it anywhere; the position survives restarts and display changes.
- Bars turn muted amber at 80% and soft red at 95%.

## Build & install

```bash
./scripts/make-app.sh
cp -R "build/Claude Usage Pill.app" /Applications/
open "/Applications/Claude Usage Pill.app"
```

Approve the keychain prompt with **Always Allow** (it re-appears once per
rebuild — each build has a fresh ad-hoc signature). Enable **Launch at Login**
from the gauge icon in the menu bar (works only from /Applications).

## Develop

```bash
swift test          # 41 unit tests (decoding, state machine, formatting, geometry)
swift build && .build/debug/ClaudeUsagePill
```

`scripts/probe-usage-api.sh` prints the live usage-endpoint response and the
credential key structure (no secret values) — useful if the API shape changes.

## Uninstall

Quit from the menu-bar gauge icon, toggle Launch at Login off first if you
enabled it, then delete `/Applications/Claude Usage Pill.app` and
`defaults delete pl.bbi.claude-usage-pill`.
