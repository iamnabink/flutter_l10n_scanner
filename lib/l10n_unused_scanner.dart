import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:yaml/yaml.dart';

/// Finds localization keys used in Dart source content.
///
/// Supports single-line and multi-line usage patterns.
Set<String> findUsedKeysInContent(String content, Set<String> allKeys) {
  if (allKeys.isEmpty) {
    return <String>{};
  }

  final String keysPattern = allKeys.map(RegExp.escape).join('|');
  if (!content.contains(RegExp(keysPattern))) {
    return <String>{};
  }

  final RegExp regex = RegExp(
    // ignore: prefer_interpolation_to_compose_strings
    r'(?:'
            r'(?:[a-zA-Z0-9_]+(?:\?)?\s*\.\s*)+'
            r'|'
            r'[a-zA-Z0-9_]+\.of\(\s*(?:context|Get\.context\!?|AppNavigation\.context|this\.context|BuildContext\s+\w+)[\s,]*\)\!?\s*\.\s*'
            r'|'
            r'[A-Za-z_]\w*\.[A-Za-z_]\w*\(\s*\)\s*\.\s*'
            r')'
            r'\s*'
            r'(' +
        keysPattern +
        r')(?:\b|\s*\()',
    multiLine: true,
    dotAll: true,
  );

  final Set<String> usedKeys = <String>{};
  for (final Match match in regex.allMatches(content)) {
    final String? key = match.group(1);
    if (key != null) {
      usedKeys.add(key);
    }
  }
  return usedKeys;
}

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
    final Set<String> nonMetaKeys = data.keys
        .where((key) => useEasyLocalization || !key.startsWith('@'))
        .toSet();
    final Set<String> removableInFile = nonMetaKeys
        .where(keysToRemove.contains)
        .toSet();

    if (nonMetaKeys.isNotEmpty && removableInFile.length == nonMetaKeys.length) {
      log(
        '⚠️ Skipping ${file.path}: removal list would delete all keys. '
        'Please review your unused-key JSON first.',
      );
      continue;
    }

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
  final List<String> dartScanDirs = useEasyLocalization
      ? <String>['lib']
      : _getDartScanDirs();

  for (final String dirPath in dartScanDirs) {
    final Directory dir = Directory(dirPath);
    if (!dir.existsSync()) {
      log('⚠️ Warning: dart scan dir `$dirPath` does not exist, skipping.');
      continue;
    }

    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (source.excludedFiles.contains(entity.path) ||
          _isIgnoredPath(entity.path, ignoreFilePatterns)) {
        continue;
      }

      final String content = entity.readAsStringSync();
      if (useEasyLocalization) {
        usedKeys.addAll(_findEasyLocalizationUsedKeys(content, allKeys));
      } else {
        usedKeys.addAll(findUsedKeysInContent(content, allKeys));
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

Set<String> _findEasyLocalizationUsedKeys(String content, Set<String> allKeys) {
  if (allKeys.isEmpty) {
    return <String>{};
  }

  final String keysPattern = allKeys.map(RegExp.escape).join('|');
  if (!content.contains(RegExp(keysPattern))) {
    return <String>{};
  }

  final RegExp regex = RegExp(
    'LocaleKeys\\.($keysPattern)(?:\\.tr\\([^)]*\\)|\\.plural\\([^)]*\\))?|'
    '(?:context|this)\\.tr\\([\'"]($keysPattern)[\'"]\\)|'
    'tr\\([\'"]($keysPattern)[\'"]\\)|'
    '[\'"]($keysPattern)[\'"]\\.tr\\([^)]*\\)',
    multiLine: true,
    dotAll: true,
  );

  final Set<String> usedKeys = <String>{};
  for (final Match match in regex.allMatches(content)) {
    final String? key =
        match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);
    if (key != null && allKeys.contains(key)) {
      usedKeys.add(key);
    }
  }
  return usedKeys;
}

/// Reads dart-scan-dirs from remove_unused_localizations.yaml.
/// Returns ['lib'] if the file is missing, invalid, or the key is absent.
List<String> _getDartScanDirs() {
  const List<String> defaultDirs = <String>['lib'];
  final File configFile = File('remove_unused_localizations.yaml');
  if (!configFile.existsSync()) {
    return defaultDirs;
  }

  try {
    final String content = configFile.readAsStringSync();
    final dynamic data = loadYaml(content);
    if (data == null || data is! Map) {
      return defaultDirs;
    }

    final dynamic dartScanDirs = data['dart-scan-dirs'];
    if (dartScanDirs == null || dartScanDirs is! YamlList) {
      return defaultDirs;
    }

    final List<String> dirs = dartScanDirs
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    return dirs.isEmpty ? defaultDirs : dirs;
  } catch (_) {
    return defaultDirs;
  }
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