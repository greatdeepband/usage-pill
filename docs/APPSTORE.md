# Submitting Usage Pill to the Mac App Store

This is the runbook for the **Mac App Store edition** — a sandboxed,
providers-only build (see "What's different" below). The engineering is done;
what remains are the steps that require Apple's web UI / Xcode and the two
distribution certificates, which cannot be created headlessly without an App
Store Connect API key.

Your Team ID is **`UYPBMCLB7Y`** (PRZEMYSSLAW ROMAN WIERZBICKI).

---

## What's different about the App Store edition (read first)

The Mac App Store **requires** App Sandbox. A sandboxed app **cannot read Claude
Code's keychain credential** (it belongs to another app), so **the Claude plan
windows (session + week) are not in the App Store edition.** This was verified
empirically: the live Claude token lives only in the keychain (the
`~/.claude/.credentials.json` file is stale/expired), and the sandbox can't
reach it. The App Store edition shows **provider balances/spend only** —
DeepSeek, OpenRouter, MiniMax, OpenAI month-to-date, and any custom GET-JSON
provider, all using your own API keys stored in the app's own sandbox keychain.

The full-featured Claude version continues to ship via Developer ID direct
download (the notarized `.dmg`/`.zip`). **Be honest in the App Store
description** that this edition tracks API balances and does not read your
Claude Code subscription usage.

> **Bundle-ID decision.** The App Store edition currently uses
> `pl.bbi.usage-pill`, the same id as the direct-download app. macOS keys apps
> by bundle id, so if you want to keep **both** installed on the same Mac, edit
> `CFBundleIdentifier` in `scripts/Info-appstore.plist` to something distinct
> (e.g. `pl.bbi.usage-pill.mas`) **before** registering the App ID below.

---

## One-time setup (Apple side — mostly web UI / Xcode)

### 1. Create the two distribution certificates (Xcode, one click each)
Xcode → **Settings → Accounts** → your Apple ID → **Manage Certificates…** →
the **+** button → create each of:
- **Apple Distribution** — signs the `.app`
- **Mac Installer Distribution** — signs the `.pkg` (this is a *separate* cert; "Apple Distribution" cannot sign a pkg)

Verify they landed:
```bash
security find-identity -v | grep -E "Apple Distribution|3rd Party Mac Developer Installer"
```
You should see `Apple Distribution: … (UYPBMCLB7Y)` and
`3rd Party Mac Developer Installer: … (UYPBMCLB7Y)`.

### 2. Register the App ID
developer.apple.com → **Certificates, Identifiers & Profiles → Identifiers → +**
→ **App IDs → App** → Description "Usage Pill", **explicit** Bundle ID =
`pl.bbi.usage-pill` (or your distinct id from the note above). No special
capabilities needed (App Sandbox is an entitlement, not a capability here).

### 3. Create the Mac App Store provisioning profile
Same portal → **Profiles → + → Distribution → "Mac App Store Connect"** → pick
the App ID from step 2 → pick the **Apple Distribution** certificate → name it
"Usage Pill MAS" → Generate → **Download** the `.provisionprofile`.

### 4. Create the App Store Connect app record
appstoreconnect.apple.com → **My Apps → +** → **New App** → Platform **macOS**,
Name "Usage Pill", Primary language, the registered Bundle ID, an SKU. Note the
**numeric Apple ID** App Store Connect assigns the app (you'll need it for the
upload). (`LSApplicationCategoryType` is already set in
`scripts/Info-appstore.plist`, so you won't hit rejection ITMS-90242.)

---

## Build, sign, and package (scripted — `make-appstore.sh dist`)

Once the certs (step 1) and profile (step 3) exist:

```bash
cd "/Volumes/Media/Usage Pill"

export MAS_APP_IDENTITY="Apple Distribution: PRZEMYSSLAW ROMAN WIERZBICKI (UYPBMCLB7Y)"
export MAS_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: PRZEMYSSLAW ROMAN WIERZBICKI (UYPBMCLB7Y)"
export MAS_PROFILE="$HOME/Downloads/Usage_Pill_MAS.provisionprofile"   # the file from step 3

bash scripts/make-appstore.sh dist
```
(Use the exact identity strings from `security find-identity -v` — copy them
verbatim.) This builds with `-DMAS_BUILD`, embeds the profile at
`Contents/embedded.provisionprofile`, signs the app with **Apple Distribution**
+ the sandbox entitlements, and runs `productbuild` with the **installer** cert
to produce `build/Usage-Pill-MAS.pkg`.

> To just **sanity-check the sandboxed app locally** without any of the above,
> run `bash scripts/make-appstore.sh proof` — it signs with your existing
> Developer ID + the sandbox entitlement so you can launch it and confirm the
> provider rows work and there's no Claude section.

---

## Upload to App Store Connect

`xcrun altool` is the supported CLI uploader (it's only deprecated for
*notarization*, which is irrelevant here — **do not** run notarytool for App
Store). You can reuse the **app-specific password** you already created
(appleid.apple.com → Sign-In and Security → App-Specific Passwords); it's
account-wide, not notarization-only. Replace `<NUMERIC-APP-ID>` with the app
record's Apple ID from step 4:

```bash
xcrun altool --upload-package "build/Usage-Pill-MAS.pkg" \
  --type macos \
  -u "<your-apple-id-email>" \
  -p "<your-app-specific-password>" \
  --apple-id "<NUMERIC-APP-ID>" \
  --bundle-id "pl.bbi.usage-pill" \
  --bundle-version "1" \
  --bundle-short-version-string "1.0.0"
```
(Or drag `build/Usage-Pill-MAS.pkg` into **Transporter.app** — same result.)
Do **not** paste the password into any committed file.

After upload, the build appears in App Store Connect under your app record in a
few minutes. Add screenshots + description there and **Submit for Review**.

### Fully headless option (optional)
If you create an **App Store Connect API key** (App Store Connect → Users and
Access → Integrations → keys; download the `AuthKey_<KEYID>.p8` into
`~/.appstoreconnect/private_keys/`), the upload becomes:
```bash
xcrun altool --upload-package "build/Usage-Pill-MAS.pkg" --type macos \
  --apiKey <KEYID> --apiIssuer <ISSUER-UUID> \
  --bundle-id pl.bbi.usage-pill --bundle-version 1 --bundle-short-version-string 1.0.0
```
An API key also lets the cert/profile/app-record steps be scripted via the API
or fastlane — but the one-click Xcode + web-UI path above is simpler for a
first submission.

---

## Quick checklist

- [ ] Apple Distribution cert created (Xcode)
- [ ] Mac Installer Distribution cert created (Xcode)
- [ ] App ID `pl.bbi.usage-pill` registered
- [ ] "Mac App Store Connect" provisioning profile downloaded
- [ ] App record created in App Store Connect (note its numeric Apple ID)
- [ ] `make-appstore.sh dist` → `build/Usage-Pill-MAS.pkg`
- [ ] `xcrun altool --upload-package …` succeeds
- [ ] Screenshots + description added, Submitted for Review
