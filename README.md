# l10n_scanner

`l10n_scanner` is a pure Dart utility package for localization cleanup and migration in Flutter/Dart projects.

Repository: [iamnabink/flutter_l10n_scanner](https://github.com/iamnabink/flutter_l10n_scanner)

## Features

- Scan `Text("...")` hardcoded literals in Dart files
- Output JSON grouped by file with line numbers
- Ignore `context.l10n.*` usage
- Ignore files using glob-like patterns
- Generate ARB keys (`camelCase`) and optional metadata
- Write unused keys into JSON
- Remove unused keys from previously written JSON
- Generate ARB keys automatically from hardcoded-text JSON
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

Main commands:

```bash
dart run l10n_scanner scan-hardcoded
dart run l10n_scanner generate-arb-from-json
dart run l10n_scanner scan-unused
dart run l10n_scanner apply-unused-json
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
dart run l10n_scanner apply-unused-json --input unused_localization_keys.json
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
