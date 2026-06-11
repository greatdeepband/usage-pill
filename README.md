# Claude Usage Pill

A tiny always-on-top macOS widget showing your Claude usage as two slim bars:
the **5-hour session** window (clay) and the **weekly** limit (dusty blue).
Hover to expand it into a card with reset countdowns and data freshness.

<p align="center">
  <img src="docs/screenshot-expanded.png" width="300" alt="Claude Usage Pill, hover-expanded: Session and Week bars with reset countdowns and freshness footer">
</p>

- Floats above every window, on every Space, including over full-screen apps.
- Shows the exact percentages Claude Code's `/usage` command reports, fetched
  with your existing Claude Code login.
- Refreshes every 60 s, on wake from sleep, and on demand from the menu bar.
- Drag it anywhere; the position survives restarts and display changes.
- Bars turn muted amber at 80% and soft red at 95%.
- Native Swift, no dependencies, ~20 MB RAM, 54 unit tests.

## Requirements

- macOS 14+ (Apple Silicon; build from source)
- A Claude **Pro/Max subscription** with [Claude Code](https://claude.com/claude-code)
  logged in on the same Mac (the widget reads usage through that login —
  API-key billing has no usage windows to show)
- Xcode Command Line Tools (`swift` toolchain) to build

## Build & install

```bash
./scripts/make-signing-cert.sh   # one-time: stable signing identity (one password prompt)
./scripts/make-app.sh
cp -R "build/Claude Usage Pill.app" /Applications/
open "/Applications/Claude Usage Pill.app"
```

On first launch, approve the keychain prompt with **Always Allow**. Thanks to
the stable signing identity, that decision survives rebuilds — those two
prompts (cert trust + Always Allow) are the only ones you will ever see.
Without the cert step, builds are ad-hoc signed and each rebuild re-asks.
Enable **Launch at Login** from the gauge icon in the menu bar (works only
from /Applications). Version history: see [CHANGELOG.md](CHANGELOG.md).

## Security & privacy

- The widget reads the OAuth token Claude Code stores in your keychain
  (item `Claude Code-credentials`) and uses it for exactly one thing: the
  usage query. Access is **strictly read-only** — it never writes to the
  keychain, never refreshes or stores tokens elsewhere, and never logs them.
- Credentials are cached in memory and re-read only when the token rotates,
  so the keychain is touched about twice a day.
- The only network traffic is HTTPS to `api.anthropic.com`.
- `scripts/make-signing-cert.sh` adds a local self-signed certificate to your
  *user* trust store for code signing only — read it before running, as you
  should for anything touching your trust settings.

## Develop

```bash
swift test          # 54 unit tests (decoding, credentials, state machine, formatting, geometry)
swift build && .build/debug/ClaudeUsagePill
```

`scripts/probe-usage-api.sh` prints the live usage-endpoint response and the
credential key structure (no secret values) — useful if the API shape changes.

## Uninstall

Quit from the menu-bar gauge icon, toggle Launch at Login off first if you
enabled it, then delete `/Applications/Claude Usage Pill.app` and
`defaults delete pl.bbi.claude-usage-pill`.

## Disclaimer

This is an unofficial, personal-use tool, not affiliated with or endorsed by
Anthropic. It calls the same endpoint Claude Code's `/usage` command uses,
which is not a documented public API and may change or stop working at any
time. If it breaks, run `scripts/probe-usage-api.sh` and compare the response
shape with `Tests/UsageCoreTests/Fixtures.swift`.

## License

[MIT](LICENSE)
