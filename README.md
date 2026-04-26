# l10n_scanner

`l10n_scanner` is a pure Dart utility package for localization cleanup and migration in Flutter/Dart projects.

Repository: [iamnabink/flutter_l10n_scanner](https://github.com/iamnabink/flutter_l10n_scanner)

## Features

- Scan `Text("...")` hardcoded literals in Dart files
- Output JSON grouped by file with line numbers
- Ignore already translated usage (`context.l10n.*`)
- Ignore files using glob-like patterns
- Generate ARB keys (`camelCase`) and optional metadata
- Read hardcoded report JSON and generate ARB from it
- Write unused keys into JSON
- Remove unused keys from previously written JSON (`.arb` or easy_localization `.json`)
- Support `remove_unused_localizations.yaml` `dart-scan-dirs` for unused-key scanning
- Better multiline/localization-access key detection to avoid false unused removals
- Safety guard: skips destructive remove-all operations per localization file
- Optional unsafe auto-replace (manual review recommended first)

## Installation

Install from pub:

```bash
dart pub add l10n_scanner
```

or (Flutter):

```bash
flutter pub add l10n_scanner
```

Install directly from GitHub (if needed):

```yaml
dependencies:
  l10n_scanner:
    git:
      url: https://github.com/iamnabink/flutter_l10n_scanner.git
```

Then run:

```bash
dart pub get
```

You can run the CLI after adding the package:

```bash
dart run l10n_scanner --help
```

For local development inside this repository:

```bash
dart run bin/l10n_scanner.dart --help
```

## Usage

### Command overview

- `scan-hardcoded`: scans Dart files for `Text("...")`, writes hardcoded text report JSON.
- `generate-arb-from-json`: reads hardcoded report JSON and writes generated ARB keys.
- `scan-unused`: scans code usage and writes unused localization keys into JSON.
- `remove-unused-json`: removes only listed keys from localization files using JSON input, then automatically re-runs `scan-unused` to refresh the same JSON file.

Main commands:

```bash
dart run l10n_scanner scan-hardcoded
dart run l10n_scanner generate-arb-from-json
dart run l10n_scanner scan-unused
dart run l10n_scanner remove-unused-json
```

### Recommended safe flow (no blind replace)

```bash
dart run l10n_scanner scan-hardcoded --output hardcoded_texts_report.json --fail-on-found
dart run l10n_scanner generate-arb-from-json --input hardcoded_texts_report.json --arb-file lib/l10n/app_en.arb --with-metadata
```

### Ignore specific files

```bash
dart run l10n_scanner scan-hardcoded --ignore-files "lib/generated/*,lib/**/mock_*.dart"
```

### Unused keys JSON workflow

```bash
dart run l10n_scanner scan-unused --output unused_localization_keys.json
dart run l10n_scanner remove-unused-json --input unused_localization_keys.json
```

`remove-unused-json` automatically refreshes `unused_localization_keys.json` after removal.

Optional scan directories config (`remove_unused_localizations.yaml`):

```yaml
dart-scan-dirs:
  - lib
  - packages
```

### Optional unsafe replacement

```bash
dart run l10n_scanner scan-hardcoded --unsafe-replace
```

Use `--unsafe-replace` only after reviewing generated JSON/ARB.

## CLI help

```bash
dart run l10n_scanner --help
```
