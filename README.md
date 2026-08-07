# RunwayGauge

macOS Notification Center widgets for service usage. The first widget shows
Claude Code subscription limits for the 5-hour session and 7-day windows.

![Claude Code usage widget — small and medium](docs/widget-preview.png)

## Requirements

macOS 14+, Xcode, `jq`, and `xcodegen`:

    brew install xcodegen jq

## Install from release

1. Download `RunwayGauge-<version>.dmg` from the project's GitHub Releases page.
2. Open the DMG and drag `RunwayGauge.app` to Applications.
3. Launch the app. macOS Gatekeeper may block the ad-hoc signed build the first time — right-click the app → **Open** → **Open** again to confirm.
4. Click **Set up data collection** in the app. This copies bundled helper scripts to Application Support and installs the statusline writer and background poller.
5. Add the small or medium widget from Notification Center → **Edit Widgets** → **RunwayGauge**.

**Requires `jq` for helper setup only** (`brew install jq`) — statusline install edits Claude `settings.json`; poll/write use the Swift helper. The app and LaunchAgent search `/opt/homebrew/bin`, `/usr/local/bin`, and system paths.

## Build and install

    ./scripts/build-and-install.sh

This installs `RunwayGauge.app` in `/Applications` and launches it once so
the widget registers. Add the small or medium widget from Notification Center
→ **Edit Widgets** → **RunwayGauge**.

## Accounts and data collection

Open **Settings** in RunwayGauge to discover Claude accounts or add one with
its exact config-directory path and Keychain service/account. Custom Claude
directory names are not assumed or hardcoded: add the directory explicitly,
then run **Set up helpers**. After adding, editing, or removing a config
directory, run **Reconfigure helpers** so the statusline and poller match the
current registry.

Each account reports separate source and usage health:

- **Ready** has both a config directory and Keychain credentials, so statusline
  and idle polling are available.
- **Statusline only** (config-only) records while Claude Code runs but cannot
  poll while idle.
- **Poller only** (Keychain-only) can refresh while idle but has no config
  directory in which to install the statusline.

Pin accounts to include them in the widget, then select one in Settings or use
the widget's cycle control. Selection is shared by every placed RunwayGauge
widget. Optional rotation advances through pinned accounts on a best-effort
WidgetKit timeline; macOS may deliver entries late. The minimum interval is
five minutes (300 seconds).

**Refresh usage now** in Settings forces an immediate poll; meter visibility toggles live under Notification Center → **Edit Widgets** → **RunwayGauge**.

The setup button copies the bundled helpers to Application Support, preserves
and backs up existing Claude `settings.json` statuslines, and installs the
background poller. The registry and per-account usage files live in the widget
extension container:

    ~/Library/Containers/com.mirabilia.RunwayGauge.UsageWidget/Data/Library/Application Support/RunwayGauge/accounts.json
    ~/Library/Containers/com.mirabilia.RunwayGauge.UsageWidget/Data/Library/Application Support/RunwayGauge/usage-acc_<id>.json

On first multi-account setup, an existing unscoped `claude-code.json` is moved
to `claude-code.legacy.json`. Its account provenance is ambiguous, so it is
archived rather than displayed under a guessed account.

The host app is intentionally unsandboxed so it can manage account settings,
inspect health, and install helpers. The widget extension remains sandboxed.

## Tests

    (cd Core && swift test)
    ./tests/test-writer.sh
    ./tests/test-poller.sh
    ./tests/test-helper-lifecycle.sh
    ./tests/test-helper-setup.sh
    ./tests/test-helper-bundle-sync.sh
    ./tests/test-cap-output.sh

## Adding another source

Sources are panes inside one widget and share `UsageCore`: add a writer that
produces the same JSON contract under a new filename, add a pane view, and add
a switcher (`Button` + `AppIntent`, or rotating timeline entries). Keep the
widget kind string as `"UsageWidget"`; changing it orphans already-placed
widgets.

## CI and releases

Commits on `main` use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `docs:`, `test:`). release-please reads these to bump semver, update `CHANGELOG.md`, and open a Release PR.

Flow:

1. Merge conventional commits to `main` with the **`ci / test`** branch protection check passing.
2. After `main` CI succeeds, release-please opens or updates a Release PR (version bump + changelog).
3. Merge the Release PR → tag `vMAJOR.MINOR.PATCH` and a GitHub Release are created.
4. Publishing the release triggers `release.yml`, which builds the app, packages a DMG, and uploads `RunwayGauge-<version>.dmg` to the release assets.

Release notes for ad-hoc signed builds include a Gatekeeper notice.

## Release automation token

`release-please.yml` uses the repository's built-in **`GITHUB_TOKEN`** — no custom secret is required. The workflow grants `contents: write`, `issues: write`, and `pull-requests: write` so release-please can open Release PRs and create GitHub Releases.

**Optional `RELEASE_PLEASE_TOKEN`:** GitHub does not run downstream workflows for some resources created by `GITHUB_TOKEN` (for example, CI on a Release PR or `release.yml` on publish). This project is wired to use `GITHUB_TOKEN` by default; if those chained workflows do not fire in your repository, add a repository secret named `RELEASE_PLEASE_TOKEN` containing a fine-grained personal access token with **Contents**, **Pull requests**, and **Issues** read/write access, and pass it to the release-please action's `token` input. PAT-created events behave like a user action and can trigger workflows that `GITHUB_TOKEN` cannot.

**Rotation (PAT only):** create a new PAT with the same permissions, update the `RELEASE_PLEASE_TOKEN` secret, verify the next release-please run succeeds, then revoke the old PAT.

## Future signing secrets

Developer ID signing and notarization are stubbed but not implemented. Leave all of these repository secrets empty for the supported ad-hoc release path:

| Secret | Purpose |
|--------|---------|
| `APPLE_CERTIFICATE` | Base64-encoded `.p12` signing certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `APPLE_SIGNING_IDENTITY` | Developer ID Application identity name |
| `APPLE_API_KEY` | App Store Connect API key (`.p8` contents) |
| `APPLE_API_KEY_ID` | API key ID |
| `APPLE_API_ISSUER` | API issuer ID |

If any signing or notarization secret is set before its workflow step is implemented, the release job fails intentionally rather than publishing an ad-hoc build as signed.
