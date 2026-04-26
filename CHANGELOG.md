# Changelog

All notable changes to this package are documented in this file.

## 0.1.0

- Add standalone CLI commands for localization workflows:
  - `scan-hardcoded`
  - `generate-arb-from-json`
  - `scan-unused`
  - `apply-unused-json`
- Add hardcoded text scanner with file grouping, line numbers, and per-file de-duplication.
- Add ignore-file pattern support for hardcoded and unused scans.
- Add JSON-first workflow:
  - write hardcoded strings to JSON
  - write unused keys to JSON
  - remove unused keys using JSON input
- Add ARB key generation from hardcoded JSON with optional metadata (`@key`).
- Add optional unsafe auto-replace (`Text("...")` to `Text(context.l10n.key)`) with explicit warning.
- Update package metadata, repository links, and README usage guides.

## 0.0.1

- Initial package scaffold.
