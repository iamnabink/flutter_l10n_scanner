import 'dart:convert';
import 'dart:io';
import 'src/dart_comment_sanitizer.dart';

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
  _coolLog('🔍 Starting hardcoded text scan in `$libDirPath`...');

  // Matches Text("...") or Text('...') with any trailing arguments.
  final RegExp textLiteralPattern = RegExp(
    r'''(?<!\w)Text\(\s*(["'])(.+?)\1''',
  );

  // Matches common named string parameters that typically render visible text.
  final RegExp namedParamPattern = RegExp(
    r'''(?:hintText|labelText|title|label|hint|tooltip|semanticsLabel|message|helperText|counterText|prefixText|suffixText|errorText|placeholderText)\s*:\s*(["'])(.+?)\1''',
  );

  final Directory libDir = Directory(libDirPath);
  final Map<String, dynamic> result = <String, dynamic>{};

  if (!libDir.existsSync()) {
    _coolLog('❌ Directory not found: `$libDirPath`');
    return false;
  }

  for (final FileSystemEntity entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (_isIgnoredPath(entity.path, ignoreFilePatterns)) {
      continue;
    }

    final String sanitizedContent = stripDartComments(entity.readAsStringSync());
    final List<String> lines = sanitizedContent.split('\n');
    final List<Map<String, dynamic>> texts = <Map<String, dynamic>>[];
    final Set<String> seenTexts = <String>{};

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];

      // Skip lines that reference l10n-translated values entirely.
      if (line.contains('context.l10n.') || line.contains('.l10n.')) {
        continue;
      }

      for (final RegExpMatch m in textLiteralPattern.allMatches(line)) {
        _collectLiteral(m.group(2), i + 1, seenTexts, texts);
      }

      for (final RegExpMatch m in namedParamPattern.allMatches(line)) {
        _collectLiteral(m.group(2), i + 1, seenTexts, texts);
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
  final int fileCount = result.length;
  final int totalTexts = result.values
      .whereType<Map<String, dynamic>>()
      .map((entry) => (entry['texts'] as List<dynamic>? ?? <dynamic>[]).length)
      .fold(0, (sum, count) => sum + count);
  _coolLog('📝 Report generated: ${reportFile.path}');
  _coolLog('📊 Found $totalTexts unique hardcoded texts across $fileCount files.');

  if (generateArb) {
    generateArbFromHardcodedJson(
      hardcodedJsonPath: reportOutputPath,
      arbFilePath: arbFilePath,
      withMetadata: withMetadata,
    );
  }

  if (unsafeReplace) {
    _coolLog(
      '⚠️ Unsafe replacement is enabled. Review generated JSON/ARB before applying.',
    );
    final int changedFiles = _replaceTextLiterals(
      libDir: libDir,
      textLiteralPattern: textLiteralPattern,
      ignoreFilePatterns: ignoreFilePatterns,
    );
    _coolLog('🛠️ Replaced literals in $changedFiles Dart files.');
  }

  if (result.isNotEmpty && failOnFound) {
    _coolLog('❌ Hardcoded texts found!');
    exitCode = 1;
  }

  _coolLog('✅ Hardcoded scan complete.');
  return result.isNotEmpty;
}

void generateArbFromHardcodedJson({
  required String hardcodedJsonPath,
  String arbFilePath = 'lib/l10n/app_en.arb',
  bool withMetadata = false,
}) {
  final File reportFile = File(hardcodedJsonPath);
  if (!reportFile.existsSync()) {
    _coolLog('❌ Hardcoded JSON file not found at `${reportFile.path}`');
    return;
  }

  final String reportContent = reportFile.readAsStringSync().trim();
  if (reportContent.isEmpty) {
    _coolLog('❌ Hardcoded JSON file is empty at `${reportFile.path}`');
    return;
  }

  final Map<String, dynamic> reportData =
      json.decode(reportContent) as Map<String, dynamic>;
  final Map<String, dynamic> arbEntries = _buildArbEntries(
    reportData,
    withMetadata: withMetadata,
  );
  _coolLog('🧩 Generated ${arbEntries.length ~/ (withMetadata ? 2 : 1)} ARB keys from JSON.');
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
  _coolLog('💾 ARB updated: ${arbFile.path}');
}

/// Collects a matched string literal into [texts] if it passes all filters.
///
/// Filters out:
/// - null / empty strings
/// - strings containing l10n references
/// - strings shorter than 2 characters
/// - strings that are purely numeric or symbolic (no letters)
/// - strings containing Dart interpolation (`$`) — these are partially dynamic
/// - duplicates within the same file (tracked via [seen])
void _collectLiteral(
  String? literal,
  int lineNumber,
  Set<String> seen,
  List<Map<String, dynamic>> texts,
) {
  if (literal == null || literal.isEmpty) return;
  if (literal.contains('l10n.')) return;
  if (literal.trim().length < 2) return;
  if (!literal.contains(RegExp(r'[a-zA-Z]'))) return;
  if (literal.contains(r'$')) return;
  if (!seen.add(literal)) return;
  texts.add(<String, dynamic>{'text': literal, 'line': lineNumber});
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
    // Replace only in comment-free positions by building an offset-aware map.
    final String sanitized = stripDartComments(original);
    final StringBuffer replaced = StringBuffer();
    int cursor = 0;
    for (final RegExpMatch match in textLiteralPattern.allMatches(sanitized)) {
      final String? text = match.group(2);
      if (text == null ||
          text.contains('l10n.') ||
          text.trim().length < 2 ||
          !text.contains(RegExp(r'[a-zA-Z]')) ||
          text.contains(r'$')) {
        continue;
      }
      final String? key = _toCamelCase(text);
      if (key == null) continue;
      replaced.write(original.substring(cursor, match.start));
      replaced.write('Text(context.l10n.$key)');
      cursor = match.end;
      // Consume any trailing `)` from the original Text() call.
      final int closeIdx = original.indexOf(')', cursor);
      if (closeIdx != -1) cursor = closeIdx + 1;
    }
    replaced.write(original.substring(cursor));
    final String replacedStr = replaced.toString();

    if (replacedStr == original) {
      continue;
    }

    entity.writeAsStringSync(replacedStr);
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

void _coolLog(String message) {
  stdout.writeln(message);
}