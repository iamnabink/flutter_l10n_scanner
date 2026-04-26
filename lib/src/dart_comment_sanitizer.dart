/// Strips Dart single-line (`//`) and multi-line (`/* */`) comments from
/// [source] while preserving string literals (including raw strings and
/// triple-quoted strings) and newlines.
///
/// Comment content is replaced with spaces so that column positions are
/// preserved — only newlines inside comments are kept as-is.
String stripDartComments(String source) {
  final StringBuffer output = StringBuffer();
  int i = 0;

  while (i < source.length) {
    final String ch = source[i];

    // ── Raw strings: r'...', r"...", r'''...''', r"""...""" ────────────────
    // Backslash has NO special meaning inside raw strings.
    if (ch == 'r' && i + 1 < source.length) {
      final String q = source[i + 1];
      if (q == '"' || q == "'") {
        // Check for triple-quote raw string.
        final bool isTriple = i + 3 < source.length &&
            source[i + 2] == q &&
            source[i + 3] == q;
        if (isTriple) {
          output.write('r$q$q$q');
          i += 4;
          while (i < source.length) {
            if (source[i] == q &&
                i + 2 < source.length &&
                source[i + 1] == q &&
                source[i + 2] == q) {
              output.write('$q$q$q');
              i += 3;
              break;
            }
            output.write(source[i] == '\n' ? '\n' : source[i]);
            i++;
          }
          continue;
        }
        // Single-quoted raw string.
        output.write('r$q');
        i += 2;
        while (i < source.length) {
          if (source[i] == q) {
            output.write(q);
            i++;
            break;
          }
          output.write(source[i] == '\n' ? '\n' : source[i]);
          i++;
        }
        continue;
      }
    }

    // ── Regular triple-quoted strings: '''...''' and """...""" ─────────────
    if ((ch == '"' || ch == "'") &&
        i + 2 < source.length &&
        source[i + 1] == ch &&
        source[i + 2] == ch) {
      final String q = ch;
      output.write('$q$q$q');
      i += 3;
      bool escaped = false;
      while (i < source.length) {
        final String c = source[i];
        if (escaped) {
          output.write(c == '\n' ? '\n' : c);
          escaped = false;
          i++;
          continue;
        }
        if (c == r'\') {
          escaped = true;
          output.write(c);
          i++;
          continue;
        }
        if (c == q &&
            i + 2 < source.length &&
            source[i + 1] == q &&
            source[i + 2] == q) {
          output.write('$q$q$q');
          i += 3;
          break;
        }
        output.write(c == '\n' ? '\n' : c);
        i++;
      }
      continue;
    }

    // ── Regular quoted strings: '...' and "..." ────────────────────────────
    if (ch == '"' || ch == "'") {
      final String q = ch;
      output.write(q);
      i++;
      bool escaped = false;
      while (i < source.length) {
        final String c = source[i];
        if (escaped) {
          output.write(c);
          escaped = false;
          i++;
          continue;
        }
        if (c == r'\') {
          escaped = true;
          output.write(c);
          i++;
          continue;
        }
        output.write(c);
        if (c == q) {
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    // ── Single-line comment: // ─────────────────────────────────────────────
    if (ch == '/' && i + 1 < source.length && source[i + 1] == '/') {
      output.write('  ');
      i += 2;
      while (i < source.length && source[i] != '\n') {
        output.write(' ');
        i++;
      }
      continue;
    }

    // ── Multi-line comment: /* */ ───────────────────────────────────────────
    if (ch == '/' && i + 1 < source.length && source[i + 1] == '*') {
      output.write('  ');
      i += 2;
      while (i < source.length) {
        if (source[i] == '*' && i + 1 < source.length && source[i + 1] == '/') {
          output.write('  ');
          i += 2;
          break;
        }
        output.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    output.write(ch);
    i++;
  }

  return output.toString();
}
