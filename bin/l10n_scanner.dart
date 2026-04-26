import 'dart:io';
import 'package:l10n_scanner/l10n_scanner.dart';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final String command = args.first;
  final Map<String, String> options = _parseOptions(args.skip(1).toList());

  switch (command) {
    case 'scan-hardcoded':
      runHardcodedTextScanner(
        libDirPath: options['lib-dir'] ?? 'lib',
        reportOutputPath: options['output'] ?? 'hardcoded_texts_report.json',
        failOnFound: _asBool(options, 'fail-on-found'),
        generateArb: _asBool(options, 'generate-arb'),
        arbFilePath: options['arb-file'] ?? 'lib/l10n/app_en.arb',
        withMetadata: _asBool(options, 'with-metadata'),
        unsafeReplace: _asBool(options, 'unsafe-replace'),
        ignoreFilePatterns: _listOption(options, 'ignore-files'),
      );
      return;
    case 'generate-arb-from-json':
      generateArbFromHardcodedJson(
        hardcodedJsonPath: options['input'] ?? 'hardcoded_texts_report.json',
        arbFilePath: options['arb-file'] ?? 'lib/l10n/app_en.arb',
        withMetadata: _asBool(options, 'with-metadata'),
      );
      return;
    case 'scan-unused':
      writeUnusedKeysJson(
        useEasyLocalization: _asBool(options, 'use-easy-localization'),
        easyLocalizationPath: options['easy-localization-path'],
        outputJsonPath: options['output'] ?? 'unused_localization_keys.json',
        ignoreFilePatterns: _listOption(options, 'ignore-files'),
      );
      return;
    case 'remove-unused-json':
      removeUnusedKeysFromJson(
        inputJsonPath: options['input'] ?? 'unused_localization_keys.json',
        useEasyLocalization: _asBool(options, 'use-easy-localization'),
        easyLocalizationPath: options['easy-localization-path'],
      );
      return;
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      exitCode = 64;
  }
}

bool _asBool(Map<String, String> options, String key) {
  return options.containsKey(key);
}

List<String> _listOption(Map<String, String> options, String key) {
  final String? raw = options[key];
  if (raw == null || raw.trim().isEmpty) {
    return const <String>[];
  }
  return raw
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

Map<String, String> _parseOptions(List<String> args) {
  final Map<String, String> options = <String, String>{};
  int i = 0;

  while (i < args.length) {
    final String token = args[i];
    if (!token.startsWith('--')) {
      i++;
      continue;
    }

    final String trimmed = token.substring(2);
    if (trimmed.contains('=')) {
      final List<String> parts = trimmed.split('=');
      final String key = parts.first;
      final String value = parts.skip(1).join('=');
      options[key] = value;
      i++;
      continue;
    }

    final String key = trimmed;
    final bool hasValue = i + 1 < args.length && !args[i + 1].startsWith('--');
    if (hasValue) {
      options[key] = args[i + 1];
      i += 2;
    } else {
      options[key] = 'true';
      i++;
    }
  }

  return options;
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run l10n_scanner <command> [options]

Commands:
  scan-hardcoded          Detect hardcoded Text("...") and write JSON.
  generate-arb-from-json  Generate ARB keys from hardcoded JSON report.
  scan-unused             Write unused localization keys into JSON.
  remove-unused-json      Remove keys from ARB/JSON using unused-key JSON.

scan-hardcoded options:
  --lib-dir <path>           Directory to scan (default: lib)
  --output <path>            Report output path (default: hardcoded_texts_report.json)
  --fail-on-found            Exit with code 1 when hardcoded text is found
  --generate-arb             Generate ARB entries from generated JSON report
  --arb-file <path>          ARB file output (default: lib/l10n/app_en.arb)
  --with-metadata            Add @key metadata with source description
  --ignore-files <patterns>  Comma-separated glob-like ignores
  --unsafe-replace           Risky auto replace. Review JSON/ARB first.

generate-arb-from-json options:
  --input <path>             Hardcoded JSON input (default: hardcoded_texts_report.json)
  --arb-file <path>          ARB file output (default: lib/l10n/app_en.arb)
  --with-metadata            Add @key metadata with source description

scan-unused options:
  --output <path>            Output JSON path (default: unused_localization_keys.json)
  --use-easy-localization    Scan easy_localization usage patterns
  --easy-localization-path   Localization directory for easy_localization
  --ignore-files <patterns>  Comma-separated glob-like ignores

remove-unused-json options:
  --input <path>             Unused-key JSON input (default: unused_localization_keys.json)
  --use-easy-localization    Scan easy_localization usage patterns
  --easy-localization-path   Localization directory for easy_localization
''');
}
