# Codex Usage for macOS

[中文](README.md) · [Download](https://github.com/WangSH-666/codex-usage-widget/releases/latest) · [MIT](LICENSE)

A native SwiftUI/AppKit desktop card for Codex. See your remaining **5-hour and weekly allowances**, with an optional rolling 24-hour local token total. Built with Liquid Glass and no third-party runtime dependencies.

![Codex Usage](docs/images/quota-light.png)

Screenshots use synthetic demo data.

## Install

Requires **macOS 26+** and an installed, signed-in Codex app or CLI. Codex bundled with ChatGPT.app is also supported. The first downloadable build targets Apple Silicon.

Download the ZIP from [Releases](https://github.com/WangSH-666/codex-usage-widget/releases), unzip it, and move **Codex Usage.app** to Applications. Open it to show the card and menu-bar icon. This is a standalone desktop card, not a WidgetKit gallery extension.

The download is ad-hoc signed and is not Apple-notarized. If macOS blocks the first launch, verify the release SHA-256 checksum before using System Settings → Privacy & Security → Open Anyway, or build from source.

## Controls

Drag anywhere to move the card. Right-click or use the menu-bar icon to change layout, appearance, background opacity (0–100%), six coordinated color presets or individual ring colors, refresh interval, and window level. Text and rings remain legible when the background fades. Low allowance (≤20%) uses orange. Reset times use your Mac's local time zone.

When always-on-top is off, the card stays at desktop level and never covers normal or full-screen app windows. Enabling always-on-top explicitly allows a floating card, including full-screen spaces. Preferences and position persist. No Dock icon or automatic login startup. Reopen the app from Applications after quitting.

## Updates

Choose “检查更新…” (Check for Updates) in the context or menu-bar menu. See the latest public version and release notes, then download the matching archive. Quit the app, replace it in Applications, and reopen; preferences persist. Checks contact only GitHub’s public release endpoint on demand and send no account, session, or usage data. Installation is manual.

Appearance changes apply immediately; system mode follows macOS appearance changes while the app is inactive.

## Privacy and limits

Local token totals come from read-only Codex session logs under `CODEX_HOME` or `~/.codex`; repeated snapshots and forked history are deduplicated. Totals cover visible logs on this Mac, not other devices.

Account limits are read through the installed Codex app-server using the existing login session. No API key, model calls, credential storage, telemetry, or log uploading. Unknown or expired limits show a dash. Account limits refresh every 30 seconds; temporary failures retry after 10 seconds.

## Build

Requires Swift 6.2+ and the macOS 26+ SDK (Command Line Tools or Xcode). No third-party Swift packages.

```sh
git clone https://github.com/WangSH-666/codex-usage-widget.git
cd codex-usage-widget
bash scripts/test.sh
bash scripts/build.sh
open 'dist/Codex Usage.app'
# Create an app ZIP and SHA-256 checksum:
bash scripts/package.sh
```

See [development](docs/DEVELOPMENT.md), [architecture](docs/ARCHITECTURE.md), [contributing](CONTRIBUTING.md), and [changelog](CHANGELOG.md).

An independent community project, not affiliated with OpenAI. Licensed under [MIT](LICENSE).
