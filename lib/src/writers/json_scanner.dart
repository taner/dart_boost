/// A tolerant, offset-preserving scanner for JSON-with-comments.
///
/// No format-preserving JSONC editor exists in Dart -- `json5` and `toml` both
/// destroy comments on re-encode, and `yaml_edit` has no JSON equivalent. So
/// edits are surgical textual splices, and this is the scanner they splice
/// against.
///
/// The core trick (stolen from Boost's `findCommaInsertionPoint`) is the
/// *mask*: a same-length copy of the source in which comment bodies and string
/// bodies become spaces. Every byte offset in the mask is valid in the source,
/// so structural scanning can be done on the mask and text can be read from
/// the source.
class JsonMask {
  JsonMask._(this.source, this.masked);

  factory JsonMask(String source) {
    final buffer = List<String>.filled(source.length, ' ');
    var i = 0;

    void copy(int index) => buffer[index] = source[index];

    while (i < source.length) {
      final char = source[i];

      if (char == '"' || char == "'") {
        // Keep the delimiters -- keys still need to be locatable -- but blank
        // the body so a `}` or `//` inside a string cannot confuse depth.
        copy(i);
        final quote = char;
        i++;
        while (i < source.length) {
          if (source[i] == '\\' && i + 1 < source.length) {
            i += 2;
            continue;
          }
          if (source[i] == quote) {
            copy(i);
            i++;
            break;
          }
          if (source[i] == '\n') copy(i);
          i++;
        }
        continue;
      }

      if (char == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        continue;
      }

      if (char == '/' && i + 1 < source.length && source[i + 1] == '*') {
        i += 2;
        while (i < source.length) {
          if (source[i] == '*' &&
              i + 1 < source.length &&
              source[i + 1] == '/') {
            i += 2;
            break;
          }
          if (source[i] == '\n') copy(i);
          i++;
        }
        continue;
      }

      copy(i);
      i++;
    }

    return JsonMask._(source, buffer.join());
  }

  final String source;

  /// Same length as [source]; comment and string bodies are spaces, newlines
  /// are preserved so line-oriented reasoning still works.
  final String masked;

  int get length => source.length;

  bool _isSpace(int index) {
    final char = masked[index];
    return char == ' ' || char == '\t' || char == '\n' || char == '\r';
  }

  /// First index at or after [from] that is not whitespace, or [length].
  int skipSpace(int from) {
    var i = from;
    while (i < length && _isSpace(i)) {
      i++;
    }
    return i;
  }

  /// Last non-whitespace index strictly before [before] and at or after
  /// [floor], or `-1`.
  int lastMeaningful(int before, int floor) {
    var i = before - 1;
    while (i >= floor && _isSpace(i)) {
      i--;
    }
    return i < floor ? -1 : i;
  }

  /// Index of the first top-level `{`, or `-1`.
  int findRootObject() => masked.indexOf('{');

  /// Index of the `}` matching the `{` at [open], or `-1`.
  int matchingBrace(int open) {
    var depth = 0;
    for (var i = open; i < length; i++) {
      final char = masked[i];
      if (char == '{' || char == '[') depth++;
      if (char == '}' || char == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// The members of the object whose `{` is at [open], in source order.
  ///
  /// Tolerates unquoted keys, single-quoted strings and trailing commas -- the
  /// JSON5 features these config files use in the wild. Stops at the first
  /// thing it cannot make sense of rather than throwing.
  List<JsonMember> members(int open) {
    final close = matchingBrace(open);
    if (close < 0) return const <JsonMember>[];

    final result = <JsonMember>[];
    var i = skipSpace(open + 1);

    while (i < close) {
      final memberStart = i;
      final keyStart = i;
      String name;

      final char = masked[i];
      if (char == '"' || char == "'") {
        final end = _endOfString(i);
        if (end < 0) break;
        name = _unescape(source.substring(i + 1, end));
        i = end + 1;
      } else if (_isIdentifierStart(char)) {
        var j = i;
        while (j < close && _isIdentifierPart(masked[j])) {
          j++;
        }
        name = source.substring(i, j);
        i = j;
      } else {
        break;
      }
      final keyEnd = i;

      i = skipSpace(i);
      if (i >= close || masked[i] != ':') break;
      i = skipSpace(i + 1);

      final valueStart = i;
      final valueEnd = _endOfValue(i, close);
      if (valueEnd < 0) break;
      i = valueEnd;

      final afterValue = skipSpace(i);
      final hasComma = afterValue < close && masked[afterValue] == ',';
      final memberEnd = hasComma ? afterValue + 1 : i;

      result.add(
        JsonMember(
          name: name,
          keyStart: keyStart,
          keyEnd: keyEnd,
          valueStart: valueStart,
          valueEnd: valueEnd,
          memberStart: memberStart,
          memberEnd: memberEnd,
          followedByComma: hasComma,
        ),
      );

      if (!hasComma) break;
      i = skipSpace(afterValue + 1);
    }

    return result;
  }

  int _endOfString(int start) {
    final quote = masked[start];
    for (var i = start + 1; i < length; i++) {
      if (masked[i] == quote) return i;
    }
    return -1;
  }

  /// Exclusive end offset of the value beginning at [start].
  int _endOfValue(int start, int limit) {
    if (start >= limit) return -1;
    final char = masked[start];
    if (char == '{' || char == '[') {
      final end = matchingBrace(start);
      return end < 0 ? -1 : end + 1;
    }
    if (char == '"' || char == "'") {
      final end = _endOfString(start);
      return end < 0 ? -1 : end + 1;
    }
    var i = start;
    while (i < limit &&
        masked[i] != ',' &&
        masked[i] != '}' &&
        masked[i] != ']') {
      i++;
    }
    // Trim trailing whitespace off a bare literal.
    var end = i;
    while (end > start && _isSpace(end - 1)) {
      end--;
    }
    return end == start ? -1 : end;
  }

  static final _identifierStart = RegExp(r'[A-Za-z_$]');
  static final _identifierPart = RegExp(r'[A-Za-z0-9_$]');

  static bool _isIdentifierStart(String char) =>
      _identifierStart.hasMatch(char);

  static bool _isIdentifierPart(String char) => _identifierPart.hasMatch(char);

  static String _unescape(String raw) => raw
      .replaceAll('\\"', '"')
      .replaceAll("\\'", "'")
      .replaceAll('\\\\', '\\');
}

class JsonMember {
  const JsonMember({
    required this.name,
    required this.keyStart,
    required this.keyEnd,
    required this.valueStart,
    required this.valueEnd,
    required this.memberStart,
    required this.memberEnd,
    required this.followedByComma,
  });

  final String name;
  final int keyStart;
  final int keyEnd;
  final int valueStart;
  final int valueEnd;
  final int memberStart;
  final int memberEnd;
  final bool followedByComma;
}
