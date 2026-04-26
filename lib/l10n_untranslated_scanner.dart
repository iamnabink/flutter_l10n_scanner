import 'dart:convert';
import 'dart:developer';
import 'dart:io';

/// Detects hardcoded `Text("...")` usage in Dart files and writes a report.
///
/// - Groups by file path
/// - Stores text + line number
/// - De-duplicates by text per file (keeps first seen line)
/// - Ignores already-translated usage such as `Text(context.l10n.someKey)`
/// - Optionally generates ARB entries and performs source replacement
///
/// Returns `true` when hardcoded text is found, otherwise `false`.
bool runHardcodedTextScanner({
  String libDirPath = 'lib',
  String reportOutputPath = 'hardcoded_texts_report.json',
  bool failOnFound = false,
  bool generateArb = false,
  String arbFilePath = 'lib/l10n/app_en.arb',
  bool withMetadata = false,
  bool unsafeReplace = false,
  List<String> ignoreFilePatterns = const <String>[],
}) {
  final RegExp textLiteralPattern = RegExp(
    r'''Text\(\s*(["'])(.+?)\1\s*\)''',
  );
  final Directory libDir = Directory(libDirPath);
  final Map<String, dynamic> result = <String, dynamic>{};

  if (!libDir.existsSync()) {
    log('Error: `$libDirPath` directory not found.');
    return false;
  }

  for (final FileSystemEntity entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (_isIgnoredPath(entity.path, ignoreFilePatterns)) {
      continue;
    }

    final List<String> lines = entity.readAsStringSync().split('\n');
    final List<Map<String, dynamic>> texts = <Map<String, dynamic>>[];
    final Set<String> seenTexts = <String>{};

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final Iterable<RegExpMatch> matches = textLiteralPattern.allMatches(line);

      for (final RegExpMatch match in matches) {
        final String? literal = match.group(2);
        if (literal == null || literal.isEmpty) {
          continue;
        }

        // Skip lines already using generated l10n keys or l10n interpolation.
        if (line.contains('context.l10n.') || literal.contains('l10n.')) {
          continue;
        }

        if (!seenTexts.add(literal)) {
          continue;
        }

        texts.add(<String, dynamic>{'text': literal, 'line': i + 1});
      }
    }

    if (texts.isNotEmpty) {
      result[entity.path] = <String, dynamic>{'texts': texts};
    }
  }

  final File reportFile = File(reportOutputPath);
  reportFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(result),
  );
  log('✅ Report generated: ${reportFile.path}');

  if (generateArb) {
    generateArbFromHardcodedJson(
      hardcodedJsonPath: reportOutputPath,
      arbFilePath: arbFilePath,
      withMetadata: withMetadata,
    );
  }

  if (unsafeReplace) {
    log(
      '⚠️ Unsafe replacement is enabled. Review generated JSON/ARB before applying.',
    );
    final int changedFiles = _replaceTextLiterals(
      libDir: libDir,
      textLiteralPattern: textLiteralPattern,
      ignoreFilePatterns: ignoreFilePatterns,
    );
    log('✅ Replaced literals in $changedFiles Dart files');
  }

  if (result.isNotEmpty && failOnFound) {
    log('❌ Hardcoded texts found!');
    exitCode = 1;
  }

  log('✅ Done');
  return result.isNotEmpty;
}

void generateArbFromHardcodedJson({
  required String hardcodedJsonPath,
  String arbFilePath = 'lib/l10n/app_en.arb',
  bool withMetadata = false,
}) {
  final File reportFile = File(hardcodedJsonPath);
  if (!reportFile.existsSync()) {
    log('Error: Hardcoded JSON file not found at `${reportFile.path}`');
    return;
  }

  final String reportContent = reportFile.readAsStringSync().trim();
  if (reportContent.isEmpty) {
    log('Error: Hardcoded JSON file is empty at `${reportFile.path}`');
    return;
  }

  final Map<String, dynamic> reportData =
      json.decode(reportContent) as Map<String, dynamic>;
  final Map<String, dynamic> arbEntries = _buildArbEntries(
    reportData,
    withMetadata: withMetadata,
  );
  _saveArbFile(arbFilePath, arbEntries);
}

Map<String, dynamic> _buildArbEntries(
  Map<String, dynamic> reportData, {
  required bool withMetadata,
}) {
  final Map<String, dynamic> arbData = <String, dynamic>{};
  final Set<String> usedKeys = <String>{};

  for (final MapEntry<String, dynamic> entry in reportData.entries) {
    final String path = entry.key;
    final dynamic textsData = entry.value['texts'];
    if (textsData is! List) {
      continue;
    }

    for (final dynamic item in textsData) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final String? text = item['text'] as String?;
      if (text == null || text.isEmpty) {
        continue;
      }

      final String? baseKey = _toCamelCase(text);
      if (baseKey == null) {
        continue;
      }

      String finalKey = baseKey;
      int suffix = 2;
      while (usedKeys.contains(finalKey) && arbData[finalKey] != text) {
        finalKey = '$baseKey$suffix';
        suffix++;
      }

      usedKeys.add(finalKey);
      arbData[finalKey] = text;
      if (withMetadata) {
        arbData['@$finalKey'] = <String, dynamic>{
          'description': 'Auto-generated from $path',
        };
      }
    }
  }

  return arbData;
}

void _saveArbFile(String arbFilePath, Map<String, dynamic> newEntries) {
  final File arbFile = File(arbFilePath);
  Map<String, dynamic> current = <String, dynamic>{};
  if (arbFile.existsSync()) {
    final String content = arbFile.readAsStringSync().trim();
    if (content.isNotEmpty) {
      current = json.decode(content) as Map<String, dynamic>;
    }
  }
  current.addAll(newEntries);
  arbFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(current),
  );
  log('✅ ARB updated: ${arbFile.path}');
}

int _replaceTextLiterals({
  required Directory libDir,
  required RegExp textLiteralPattern,
  required List<String> ignoreFilePatterns,
}) {
  int changedFiles = 0;

  for (final FileSystemEntity entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (_isIgnoredPath(entity.path, ignoreFilePatterns)) {
      continue;
    }

    final String original = entity.readAsStringSync();
    final String replaced = original.replaceAllMapped(textLiteralPattern, (
      Match match,
    ) {
      final String? text = match.group(2);
      if (text == null || text.contains('l10n.')) {
        return match.group(0) ?? '';
      }
      final String? key = _toCamelCase(text);
      if (key == null) {
        return match.group(0) ?? '';
      }
      return 'Text(context.l10n.$key)';
    });

    if (replaced == original) {
      continue;
    }

    entity.writeAsStringSync(replaced);
    changedFiles++;
  }

  return changedFiles;
}

String? _toCamelCase(String text) {
  final String normalized = text.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '');
  final List<String> words = normalized
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return null;
  }
  final String first = words.first.toLowerCase();
  final String rest = words
      .skip(1)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join();
  return '$first$rest';
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