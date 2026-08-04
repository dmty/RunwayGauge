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
5. Add the small or medium widget from Notification Center → Edit Widgets.

**Requires `jq` on your Mac** (`brew install jq`). The app and its LaunchAgent search standard binary locations themselves — Apple Silicon Homebrew (`/opt/homebrew/bin`), Intel Homebrew (`/usr/local/bin`), and system paths — so you do not need to modify global `launchctl` PATH.

## Build and install

    ./scripts/build-and-install.sh

This installs `RunwayGauge.app` in `/Applications` and launches it once so
the widget registers. Add the small or medium widget from Notification Center
→ Edit Widgets.

## Feed it data

    ./scripts/install-statusline.sh    # records usage while Claude Code runs
    ./scripts/install-poller.sh        # refreshes every 10 min while idle

The statusline installer preserves an existing statusline command and backs up
each `settings.json`. Undo it with:

    ./scripts/uninstall-statusline.sh

The data file is in the widget extension container:

    ~/Library/Containers/com.mirabilia.RunwayGauge.UsageWidget/Data/Library/Application Support/RunwayGauge/claude-code.json

The host app is intentionally unsandboxed so it can show whether this file is
available and current. The widget extension remains sandboxed.

## Tests

    (cd Core && swift test)     # all logic
    ./tests/test-writer.sh      # statusline writer and wrapper
    ./tests/test-poller.sh      # poller mapping

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
