import 'dart:convert';

import 'json_scanner.dart';

class SpliceResult {
  const SpliceResult.changed(this.content) : changed = true, error = null;

  const SpliceResult.unchanged(this.content) : changed = false, error = null;

  const SpliceResult.failed(this.error) : content = null, changed = false;

  /// The full new file contents, or `null` when [error] is set.
  final String? content;

  final bool changed;

  /// When set, nothing should be written: the spliced output did not re-parse.
  /// A mangled MCP config is far worse than a skipped one.
  final String? error;

  bool get ok => error == null;
}

/// Inserts or replaces MCP server entries in a JSON / JSONC config, preserving
/// everything else in the file byte-for-byte.
///
/// Parse-and-re-serialize is not an option: a real config on this machine
/// (`~/.codex/config.toml`, and the JSON ones are no better) carries
/// sentinel-comment blocks another tool depends on, which a round-trip would
/// silently delete.
class JsonConfigSplicer {
  const JsonConfigSplicer({required this.configKey});

  /// `mcpServers`, `servers` (Copilot), `context_servers` (Zed), `mcp`
  /// (OpenCode) -- the shape is identical, only the key differs.
  final String configKey;

  SpliceResult splice(String original, Map<String, Object?> servers) {
    if (servers.isEmpty) return SpliceResult.unchanged(original);

    final crlf = original.contains('\r\n');
    final source = crlf ? original.replaceAll('\r\n', '\n') : original;

    final spliced = _splice(source, servers);
    if (spliced.error != null) return spliced;

    var result = spliced.content!;
    if (!result.endsWith('\n')) result = '$result\n';

    final failure = validate(result);
    if (failure != null) {
      // Only treat a parse failure as ours when the input parsed to begin
      // with. A config that already used unquoted keys or single quotes was
      // never strict JSON, and refusing to write it would punish the user for
      // their editor's dialect.
      final inputWasStrict = validate(source) == null;
      if (inputWasStrict ||
          !structurallySound(result, servers.keys, configKey)) {
        return SpliceResult.failed('spliced output did not re-parse: $failure');
      }
    }

    if (crlf) result = result.replaceAll('\n', '\r\n');
    return result == original
        ? SpliceResult.unchanged(original)
        : SpliceResult.changed(result);
  }

  SpliceResult _splice(String source, Map<String, Object?> servers) {
    // An empty file, or one that is just `{}`, gets written fresh.
    if (source.trim().length < 3) {
      return SpliceResult.changed(_renderWholeFile(servers));
    }

    final mask = JsonMask(source);
    final rootOpen = mask.findRootObject();
    if (rootOpen < 0) {
      return const SpliceResult.failed('no JSON object found');
    }
    final rootClose = mask.matchingBrace(rootOpen);
    if (rootClose < 0) {
      return const SpliceResult.failed('unbalanced braces');
    }

    final unit = _detectIndentUnit(source);
    final rootMembers = mask.members(rootOpen);
    final config = rootMembers.where((m) => m.name == configKey).firstOrNull;

    if (config == null) {
      return SpliceResult.changed(
        _insertConfigKey(
          source,
          mask,
          rootOpen,
          rootClose,
          rootMembers,
          servers,
          unit,
        ),
      );
    }

    if (config.valueStart >= source.length ||
        mask.masked[config.valueStart] != '{') {
      return SpliceResult.failed('"$configKey" is not an object');
    }

    return SpliceResult.changed(
      _mergeIntoConfig(source, mask, config.valueStart, servers, unit),
    );
  }

  // ------------------------------------------------------------ new config

  String _renderWholeFile(Map<String, Object?> servers) =>
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{configKey: servers})}\n';

  String _insertConfigKey(
    String source,
    JsonMask mask,
    int rootOpen,
    int rootClose,
    List<JsonMember> rootMembers,
    Map<String, Object?> servers,
    String unit,
  ) {
    final entries = servers.entries
        .map(
          (e) =>
              '$unit$unit${_encodeMember(e.key, e.value, '$unit$unit', unit)}',
        )
        .join(',\n');
    final section = '$unit"$configKey": {\n$entries\n$unit}';

    if (rootMembers.isEmpty) {
      final inner = mask.masked.substring(rootOpen + 1, rootClose);
      if (inner.trim().isEmpty) {
        return source.replaceRange(rootOpen + 1, rootClose, '\n$section\n');
      }
      return source.replaceRange(rootOpen + 1, rootOpen + 1, '\n$section,');
    }

    return source.replaceRange(rootOpen + 1, rootOpen + 1, '\n$section,');
  }

  // -------------------------------------------------------- existing config

  String _mergeIntoConfig(
    String source,
    JsonMask mask,
    int open,
    Map<String, Object?> servers,
    String unit,
  ) {
    final close = mask.matchingBrace(open);
    final members = mask.members(open);
    final indent = _detectMemberIndent(source, members, open, unit);

    // Edits are collected and applied back-to-front so earlier offsets stay
    // valid.
    final edits = <_Edit>[];
    final additions = <MapEntry<String, Object?>>[];

    for (final server in servers.entries) {
      final existing = members.where((m) => m.name == server.key).firstOrNull;
      if (existing == null) {
        additions.add(server);
        continue;
      }
      // Only rewrite when the entry actually differs. Re-formatting a
      // semantically identical entry would make every `install` dirty the
      // user's diff for nothing.
      final current = _decodeSpan(
        source,
        existing.valueStart,
        existing.valueEnd,
      );
      if (_deepEquals(current, server.value)) continue;
      edits.add(
        _Edit(
          existing.valueStart,
          existing.valueEnd,
          _encodeValue(server.value, indent, unit),
        ),
      );
    }

    if (additions.isNotEmpty) {
      final payload = additions
          .map((e) => '$indent${_encodeMember(e.key, e.value, indent, unit)}')
          .join(',\n');

      if (members.isEmpty &&
          mask.masked.substring(open + 1, close).trim().isEmpty) {
        edits.add(
          _Edit(open + 1, close, '\n$payload\n${_lineIndent(source, close)}'),
        );
      } else {
        final last = mask.lastMeaningful(close, open + 1);
        final needsComma = last >= 0 && mask.masked[last] != ',';
        final commaAt = last + 1;

        // The masked tail is blank whether or not a trailing comment is there,
        // so this asks the *source*: anything non-blank before the closing
        // brace is a trailing comment, and then the comma goes ahead of it and
        // the payload after it. Naive implementations insert the payload
        // between the value and the comment and change what the comment
        // annotates.
        final tailIsBlank =
            commaAt >= close || source.substring(commaAt, close).trim().isEmpty;

        if (!needsComma) {
          edits.add(_insertBeforeClose(source, close, payload));
        } else if (tailIsBlank) {
          edits.add(_Edit(commaAt, commaAt, ',\n$payload'));
        } else {
          edits
            ..add(_insertBeforeClose(source, close, payload))
            ..add(_Edit(commaAt, commaAt, ','));
        }
      }
    }

    edits.sort((a, b) => b.start.compareTo(a.start));
    var result = source;
    for (final edit in edits) {
      result = result.replaceRange(edit.start, edit.end, edit.text);
    }
    return result;
  }

  // ------------------------------------------------------------- encoding

  String _encodeMember(String key, Object? value, String indent, String unit) =>
      '${jsonEncode(key)}: ${_encodeValue(value, indent, unit)}';

  /// Pretty-prints [value], indenting every line after the first by [indent]
  /// so the block lines up with its neighbours.
  String _encodeValue(Object? value, String indent, String unit) {
    final encoded = JsonEncoder.withIndent(unit).convert(value);
    final lines = encoded.split('\n');
    if (lines.length == 1) return encoded;
    return [
      lines.first,
      ...lines.skip(1).map((line) => '$indent$line'),
    ].join('\n');
  }

  // ------------------------------------------------------------ formatting

  static String _detectIndentUnit(String source) {
    final match = RegExp(r'\n([ \t]+)\S').firstMatch(source);
    final indent = match?.group(1);
    if (indent == null || indent.isEmpty) return '  ';
    // The first indented line is one level deep, so it *is* the unit.
    return indent;
  }

  static String _detectMemberIndent(
    String source,
    List<JsonMember> members,
    int open,
    String unit,
  ) {
    if (members.isNotEmpty) {
      return _lineIndent(source, members.first.memberStart);
    }
    return _lineIndent(source, open) + unit;
  }

  /// The leading whitespace of the line containing [offset].
  static String _lineIndent(String source, int offset) {
    final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
    var i = lineStart;
    while (i < source.length && (source[i] == ' ' || source[i] == '\t')) {
      i++;
    }
    return source.substring(lineStart, i);
  }

  /// Places [payload] as the last member of the object closed at [close].
  ///
  /// When the brace already sits alone on its own indented line, the payload
  /// goes on the line *above* it -- inserting at the brace itself would stack
  /// the closer's indentation on top of the member's.
  static _Edit _insertBeforeClose(String source, int close, String payload) {
    final indent = _lineIndent(source, close);
    final lineStart = source.lastIndexOf('\n', close - 1) + 1;
    if (lineStart + indent.length == close) {
      return _Edit(lineStart, lineStart, '$payload\n');
    }
    return _Edit(close, close, '\n$payload\n$indent');
  }

  static Object? _decodeSpan(String source, int start, int end) {
    try {
      return jsonDecode(toStrictJson(source.substring(start, end)));
    } on FormatException {
      return const Object();
    }
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  // ------------------------------------------------------------ validation

  /// Re-parses [content] the way a JSONC-aware agent would. Returns `null`
  /// when it is valid, or a message describing why it is not.
  ///
  /// This is the safety net Boost lacks. If splicing produced something that
  /// does not parse, the caller aborts that agent and leaves the file
  /// untouched -- a mangled MCP config is far worse than a skipped one.
  static String? validate(String content) {
    try {
      jsonDecode(toStrictJson(content));
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  /// A weaker check for files that were already non-strict before we touched
  /// them (unquoted keys, single-quoted strings). Rejecting those outright
  /// would abort agents whose configs were perfectly fine.
  static bool structurallySound(
    String content,
    Iterable<String> expectedKeys,
    String configKey,
  ) {
    final mask = JsonMask(content);
    final root = mask.findRootObject();
    if (root < 0) return false;
    final close = mask.matchingBrace(root);
    if (close < 0) return false;
    if (mask.lastMeaningful(mask.length, 0) != close) return false;

    final config =
        mask.members(root).where((m) => m.name == configKey).firstOrNull;
    if (config == null) return false;
    if (mask.masked[config.valueStart] != '{') return false;

    final present = mask.members(config.valueStart).map((m) => m.name).toSet();
    return expectedKeys.every(present.contains);
  }

  /// Comments out, trailing commas out -- string bodies untouched. Single pass.
  ///
  /// Public because it is the only honest way to compare "what the file says"
  /// before and after a splice in a test.
  static String toStrictJson(String content) {
    final tokens = <String>[];
    final isString = <bool>[];
    var i = 0;

    while (i < content.length) {
      final char = content[i];

      if (char == '"' || char == "'") {
        final start = i;
        i++;
        while (i < content.length) {
          if (content[i] == '\\' && i + 1 < content.length) {
            i += 2;
            continue;
          }
          if (content[i] == char) {
            i++;
            break;
          }
          i++;
        }
        tokens.add(content.substring(start, i));
        isString.add(true);
        continue;
      }

      if (char == '/' && i + 1 < content.length && content[i + 1] == '/') {
        while (i < content.length && content[i] != '\n') {
          i++;
        }
        continue;
      }

      if (char == '/' && i + 1 < content.length && content[i + 1] == '*') {
        i += 2;
        while (i < content.length &&
            !(content[i] == '*' &&
                i + 1 < content.length &&
                content[i + 1] == '/')) {
          i++;
        }
        i = i < content.length ? i + 2 : content.length;
        continue;
      }

      tokens.add(char);
      isString.add(false);
      i++;
    }

    final buffer = StringBuffer();
    for (var k = 0; k < tokens.length; k++) {
      if (!isString[k] && tokens[k] == ',') {
        var j = k + 1;
        while (j < tokens.length && !isString[j] && tokens[j].trim().isEmpty) {
          j++;
        }
        if (j < tokens.length &&
            !isString[j] &&
            (tokens[j] == '}' || tokens[j] == ']')) {
          continue;
        }
      }
      buffer.write(tokens[k]);
    }

    return buffer.toString();
  }
}

class _Edit {
  const _Edit(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}
