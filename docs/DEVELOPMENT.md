# Development and troubleshooting

## Requirements

macOS 26+, Swift 6.2+, and a macOS 26+ SDK from Command Line Tools or Xcode. The package has no third-party Swift dependencies. Build caches live in `.build`; generated apps and ZIPs live in `dist`.

```sh
bash scripts/test.sh
bash scripts/build.sh
open 'dist/Codex Usage.app'
```

The build uses the current machine's architecture. The first published binary is arm64; Intel runtime support has not been verified locally.

## Diagnostics

Right-click → “状态与说明…” for local scan and account sync status. For read-only counts and quota diagnostics:

```sh
'dist/Codex Usage.app/Contents/MacOS/CodexUsage' --snapshot
```

This output is local diagnostic data. Review it before posting publicly.

`CODEX_HOME` can select a nonstandard data directory; `CODEX_EXECUTABLE` can specify a Codex executable. Finder-launched apps normally use standard bundle/CLI discovery, since their PATH may be shorter than a terminal's.

Unknown quotas can mean no Codex login, no app-server executable, incompatible protocol changes, expired snapshots, or mismatched rate-limit windows. A different model bucket is never used as a Codex fallback.

## Visual verification and demo screenshots

Quit an existing card first; single-instance protection otherwise only shows that instance.

```sh
# Synthetic data only: no log scan or account read.
open -n 'dist/Codex Usage.app' --args --demo --ui-check /tmp/codex-usage-preview
```

The app checks both layouts, light/dark rendering, opacity endpoints, preference persistence, and custom colors; saves PNGs plus `checks.json`; then exits. `--demo` alone opens the card with sample data. Demo mode never runs the real scanners or account client. The UI check temporarily changes and then restores the app's appearance/layout/color/opacity settings.

Inspect screenshots and confirm every value in `checks.json` is true. UI screenshots require a normal macOS graphical session. Core tests and release builds run in CI without signing credentials or a Codex login.

For dragging/context-menu changes, verify actual pointer movement and menu actions: window flags and screenshot generation alone do not prove those interactions work.

## Release

Update `VERSION`, bundle metadata, displayed version strings, and `CHANGELOG.md` together. Run tests and package:

```sh
bash scripts/test.sh
bash scripts/package.sh
```

Archives are named `Codex-Usage-<version>-macOS-<architecture>.zip`, with a `.sha256` companion. Tag `v<VERSION>` to trigger the release workflow. Builds are ad-hoc signed, not notarized; distributable Developer ID signing/notarization requires a maintainer's own Apple Developer credentials.
