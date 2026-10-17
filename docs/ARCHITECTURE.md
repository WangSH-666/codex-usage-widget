# Architecture

## Application

`CodexUsage` is an accessory macOS app: a transparent, nonactivating AppKit panel hosts the SwiftUI card. A native mouse surface handles drag and context-menu events over the entire card. The menu-bar item restores a hidden card; reopening the app also shows it. Only one instance runs at a time.

`Preferences` stores layout, appearance, colors, background opacity, refresh interval, window level, and position in the app's UserDefaults domain. Background opacity is applied inside the SwiftUI background; window alpha stays at 1. Unpinned cards use desktop-icon level + 1 and exclude full-screen auxiliary behavior; pinned cards explicitly use floating level and opt into full-screen spaces. Six paired palettes persist through the same color preferences as custom colors. The card is 344 × 164 pt; its window is 360 × 180 pt including shadow insets.

## Data flow

`UsageStore` drives independent background serial queues for local scanning and account reads, publishing results on the main thread. Wake events refresh immediately. A pending manual refresh is queued if work is already running.

`UsageScanner` incrementally reads JSONL chunks from `sessions` and `archived_sessions`. It filters event envelopes, bounds line memory, computes rolling 24-hour deltas from cumulative token counts, and deduplicates snapshots and forked history. Task lifecycle counts remain available in the details dialog.

`AccountClient` locates Codex in standard application bundles or CLI paths, starts `codex app-server --listen stdio://`, completes initialize → initialized, then reads `account/rateLimits/read`. It selects only the Codex bucket, bounds transport time, and terminates its child process. It does not read auth files. Failed reads clear the prior account snapshot.

`QuotaWindow` validates window durations and expiry before exposing remaining percentages. Absolute reset labels use the current local time zone. Missing or stale values stay unknown rather than becoming 100%.

## Appearance and updates

The card uses an explicit resolved color scheme in both its AppKit host and SwiftUI environment. System mode reads the global macOS appearance preference and observes system changes; menu changes apply synchronously, while general preference updates use common run-loop modes.

The manual UpdateClient calls only GitHub’s fixed public latest-release endpoint with a bounded, ephemeral URLSession. It compares numeric stable versions, filters download assets by CPU architecture, and accepts links only within this repository. The app shows release notes and opens the matching archive or release page. Replacing the installed app is a user action.

## Distribution

`Package.swift` builds the native executable and core tests. `scripts/build.sh` assembles the `.app`, generates an icon, and applies ad-hoc signing. `scripts/package.sh` creates an app ZIP and SHA-256 checksum. GitHub Actions run tests/builds and publish archives for `v<VERSION>` tags.

Synthetic `--demo` mode supplies fixed counts and quotas without starting log scans or an account-server process, so public previews never need a real account.
