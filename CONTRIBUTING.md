# Contributing

Issues and pull requests are welcome. Include macOS version, CPU architecture, Codex installation method, and steps to reproduce. Remove account details, session contents, local paths, and credentials from logs or screenshots before sharing.

## Local checks

```sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh --skip-build
```

The app targets macOS 26+, Swift 6.2+, and has no third-party dependencies. `Sources/UsageCore` holds parsing/statistics and transport code; keep UI changes in `Sources/CodexUsage`. Add regression coverage for changes to counters, log parsing, quota selection, reset times, or process cleanup.

For UI changes, check both layouts in light/dark appearances, opacity endpoints, dragging, and context menus. Use the synthetic demo mode to create public screenshots; see [development](docs/DEVELOPMENT.md).

Keep generated applications, caches, local diagnostics, and old Windows artifacts out of commits. By contributing, you agree that your contributions are licensed under this project's MIT License.
