import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:yaml/yaml.dart';

/// Finds unused localization keys and writes them into a JSON file.
///
/// Returns the unused key set.
Set<String> writeUnusedKeysJson({
  bool useEasyLocalization = false,
  String? easyLocalizationPath,
  String outputJsonPath = 'unused_localization_keys.json',
  List<String> ignoreFilePatterns = const <String>[],
}) {
  final _UnusedScanResult scanResult = _scanUnusedKeys(
    useEasyLocalization: useEasyLocalization,
    easyLocalizationPath: easyLocalizationPath,
    ignoreFilePatterns: ignoreFilePatterns,
  );

  final List<String> sortedKeys = scanResult.unusedKeys.toList()..sort();
  final Map<String, dynamic> payload = <String, dynamic>{
    'mode': useEasyLocalization ? 'easy_localization' : 'flutter_gen',
    'unused_keys': sortedKeys,
    'count': sortedKeys.length,
  };

  final File outputFile = File(outputJsonPath);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  log('✅ Unused keys JSON written: ${outputFile.path}');
  return scanResult.unusedKeys;
}

/// Removes localization keys from localization files using a previously written JSON file.
void removeUnusedKeysFromJson({
  String inputJsonPath = 'unused_localization_keys.json',
  bool useEasyLocalization = false,
  String? easyLocalizationPath,
}) {
  final File jsonFile = File(inputJsonPath);
  if (!jsonFile.existsSync()) {
    log('Error: Unused-key JSON not found at `${jsonFile.path}`');
    return;
  }

  final Map<String, dynamic> payload =
      json.decode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
  final List<dynamic> keysRaw = (payload['unused_keys'] as List<dynamic>? ?? <dynamic>[]);
  final Set<String> keysToRemove = keysRaw
      .whereType<String>()
      .where((key) => key.trim().isNotEmpty)
      .toSet();

  if (keysToRemove.isEmpty) {
    log('No keys to remove in `${jsonFile.path}`.');
    return;
  }

  final _LocalizationSource source = _resolveLocalizationSource(
    useEasyLocalization: useEasyLocalization,
    easyLocalizationPath: easyLocalizationPath,
  );
  final List<File> localizationFiles = source.localizationFiles;
  if (localizationFiles.isEmpty) {
    log('No localization files found in ${source.localizationDir.path}');
    return;
  }

  int modifiedFiles = 0;
  int removedKeyCount = 0;

  for (final File file in localizationFiles) {
    final Map<String, dynamic> data =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    bool updated = false;

    for (final String key in keysToRemove) {
      if (!data.containsKey(key)) {
        continue;
      }
      data.remove(key);
      removedKeyCount++;
      if (!useEasyLocalization) {
        data.remove('@$key');
      }
      updated = true;
    }

    if (updated) {
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      modifiedFiles++;
    }
  }

  log('✅ Removed $removedKeyCount keys across $modifiedFiles localization files.');
}

/// Backward-compatible wrapper. Prefer [writeUnusedKeysJson] + [removeUnusedKeysFromJson].
void runLocalizationCleaner({
  bool keepUnused = false,
  bool useEasyLocalization = false,
  String? easyLocalizationPath,
}) {
  final String outputJsonPath = 'unused_localization_keys.json';
  writeUnusedKeysJson(
    useEasyLocalization: useEasyLocalization,
    easyLocalizationPath: easyLocalizationPath,
    outputJsonPath: outputJsonPath,
  );
  if (!keepUnused) {
    removeUnusedKeysFromJson(
      inputJsonPath: outputJsonPath,
      useEasyLocalization: useEasyLocalization,
      easyLocalizationPath: easyLocalizationPath,
    );
  }
}

_UnusedScanResult _scanUnusedKeys({
  required bool useEasyLocalization,
  required String? easyLocalizationPath,
  required List<String> ignoreFilePatterns,
}) {
  final _LocalizationSource source = _resolveLocalizationSource(
    useEasyLocalization: useEasyLocalization,
    easyLocalizationPath: easyLocalizationPath,
  );
  final List<File> localizationFiles = source.localizationFiles;
  if (localizationFiles.isEmpty) {
    return _UnusedScanResult(<String>{});
  }

  final Set<String> allKeys = <String>{};
  for (final File file in localizationFiles) {
    final Map<String, dynamic> data =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final Set<String> keys = useEasyLocalization
        ? data.keys.toSet()
        : data.keys.where((key) => !key.startsWith('@')).toSet();
    allKeys.addAll(keys);
  }

  if (allKeys.isEmpty) {
    return _UnusedScanResult(<String>{});
  }

  final Set<String> usedKeys = <String>{};
  final Directory libDir = Directory('lib');
  final String keysPattern = allKeys.map(RegExp.escape).join('|');

  final RegExp regex = useEasyLocalization
      ? RegExp(
          'LocaleKeys\\.($keysPattern)(?:\\.tr\\([^)]*\\)|\\.plural\\([^)]*\\))?|'
          '(?:context|this)\\.tr\\([\'"]($keysPattern)[\'"]\\)|'
          'tr\\([\'"]($keysPattern)[\'"]\\)|'
          '[\'"]($keysPattern)[\'"]\\.tr\\([^)]*\\)',
          multiLine: true,
          dotAll: true,
        )
      : RegExp(
          r'(?:'
                  r'(?:[a-zA-Z0-9_]+\s*\.)+'
                  r'|'
                  r'[a-zA-Z0-9_]+\.of\(\s*(?:context|AppNavigation\.context|this\.context|BuildContext\s+\w+),?\s*\)\!?\s*\.\s*'
                  r'|'
                  r'[a-zA-Z0-9_]+\.\w+\(\s*\)\s*\.\s*'
                  r')'
                  r'($keysPattern)\b',
          multiLine: true,
          dotAll: true,
        );

  for (final FileSystemEntity entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (source.excludedFiles.contains(entity.path) ||
        _isIgnoredPath(entity.path, ignoreFilePatterns)) {
      continue;
    }

    final String content = entity.readAsStringSync();
    if (!content.contains(RegExp(keysPattern))) {
      continue;
    }

    for (final Match match in regex.allMatches(content)) {
      if (useEasyLocalization) {
        final String? key =
            match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);
        if (key != null && allKeys.contains(key)) {
          usedKeys.add(key);
        }
      } else {
        final String? key = match.group(1);
        if (key != null) {
          usedKeys.add(key);
        }
      }
    }
  }

  return _UnusedScanResult(allKeys.difference(usedKeys));
}

_LocalizationSource _resolveLocalizationSource({
  required bool useEasyLocalization,
  required String? easyLocalizationPath,
}) {
  final File yamlFile = File('l10n.yaml');
  Directory localizationDir = Directory('lib/l10n');
  Set<String> excludedFiles = <String>{'lib/l10n/app_localizations.dart'};

  if (!useEasyLocalization && yamlFile.existsSync()) {
    final String yamlContent = yamlFile.readAsStringSync();
    final Map yamlData = loadYaml(yamlContent);
    final String arbDir = yamlData['arb-dir'] as String? ?? 'lib/l10n';
    final String outputDir = yamlData['output-dir'] as String? ?? '';
    final String outputFile =
        yamlData['output-localization-file'] as String? ?? 'app_localizations.dart';
    localizationDir = Directory(arbDir);
    excludedFiles = <String>{'$outputDir/$outputFile'};
  }

  if (useEasyLocalization) {
    localizationDir = Directory(easyLocalizationPath ?? 'assets/translations');
  }

  final List<File> localizationFiles = localizationDir
      .listSync()
      .whereType<File>()
      .where(
        (file) => useEasyLocalization
            ? file.path.endsWith('.json')
            : file.path.endsWith('.arb'),
      )
      .toList();

  return _LocalizationSource(
    localizationDir: localizationDir,
    localizationFiles: localizationFiles,
    excludedFiles: excludedFiles,
  );
}

bool _isIgnoredPath(String path, List<String> patterns) {
  if (patterns.isEmpty) {
    return false;
  }
  final String normalizedPath = path.replaceAll('\\', '/');
  for (final String rawPattern in patterns) {
    final String pattern = rawPattern.trim();
    if (pattern.isEmpty) {
      continue;
    }
    final String normalizedPattern = pattern.replaceAll('\\', '/');
    final String regexPattern = '^${RegExp.escape(normalizedPattern).replaceAll(r'\*', '.*')}\$';
    if (RegExp(regexPattern).hasMatch(normalizedPath) ||
        normalizedPath.endsWith('/$normalizedPattern') ||
        normalizedPath.endsWith(normalizedPattern)) {
      return true;
    }
  }
  return false;
}

final class _UnusedScanResult {
  const _UnusedScanResult(this.unusedKeys);

  final Set<String> unusedKeys;
}

final class _LocalizationSource {
  const _LocalizationSource({
    required this.localizationDir,
    required this.localizationFiles,
    required this.excludedFiles,
  });

  final Directory localizationDir;
  final List<File> localizationFiles;
  final Set<String> excludedFiles;
}