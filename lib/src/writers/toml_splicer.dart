import 'package:toml/toml.dart';

import 'json_splicer.dart' show SpliceResult;

/// Inserts or replaces MCP server tables in a TOML config.
///
/// TOML is genuinely easier than JSON here, so this exploits it: a
/// `[table.header]` always opens a fresh scope, which means appending
/// `[mcp_servers.dart]` at end-of-file is *always* semantically correct. Span
/// logic is only needed to remove a previous run's table before re-appending.
/// About forty lines, line-oriented, no parser -- Boost's `TomlFileWriter`
/// strategy, and it is the right one.
///
/// `package:toml` earns its place here as a validator and nothing else. A real
/// config on this machine (`~/.codex/config.toml`) carries sentinel-comment
/// blocks another tool depends on, and parse-and-re-serialize would delete
/// them.
class TomlConfigSplicer {
  const TomlConfigSplicer({required this.configKey});

  final String configKey;

  SpliceResult splice(
    String original,
    Map<String, Map<String, Object?>> servers,
  ) {
    if (servers.isEmpty) return SpliceResult.unchanged(original);

    final crlf = original.contains('\r\n');
    var content = crlf ? original.replaceAll('\r\n', '\n') : original;

    for (final server in servers.entries) {
      content = _removeTable(content, '$configKey.${server.key}');
      final trimmed = content.trimRight();
      final separator = trimmed.isEmpty ? '' : '\n\n';
      content = '$trimmed$separator${_renderTable(server.key, server.value)}\n';
    }

    final failure = validate(content);
    if (failure != null) {
      return SpliceResult.failed('spliced output did not re-parse: $failure');
    }

    if (crlf) content = content.replaceAll('\n', '\r\n');
    return content == original
        ? SpliceResult.unchanged(original)
        : SpliceResult.changed(content);
  }

  /// Drops `[<path>]` and every `[<path>.*]` sub-table, each running from its
  /// header line to the line before the next header at line start.
  String _removeTable(String content, String path) {
    final lines = content.split('\n');
    final kept = <String>[];
    var dropping = false;

    for (final line in lines) {
      final header = _headerOf(line);
      if (header != null) {
        dropping = header == path || header.startsWith('$path.');
      }
      if (!dropping) kept.add(line);
    }

    return kept.join('\n');
  }

  /// The dotted key of a `[table]` header at a line start, or `null`.
  static String? _headerOf(String line) {
    final match = RegExp(r'^\[\[?([^\]]+)\]\]?\s*(#.*)?$').firstMatch(line);
    return match?.group(1)?.trim();
  }

  String _renderTable(String key, Map<String, Object?> config) {
    final lines = <String>['[$configKey.$key]'];
    final env = config['env'];

    for (final entry in config.entries) {
      if (entry.key == 'env') continue;
      final value = entry.value;
      if (value == null) continue;
      lines.add('${entry.key} = ${formatValue(value)}');
    }

    if (env is Map && env.isNotEmpty) {
      lines
        ..add('')
        ..add('[$configKey.$key.env]');
      env.forEach((name, value) => lines.add('$name = ${formatValue(value)}'));
    }

    return lines.join('\n');
  }

  static String formatValue(Object? value) {
    if (value is String) return '"${_escape(value)}"';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return '$value';
    if (value is Iterable) {
      return '[${value.map(formatValue).join(', ')}]';
    }
    return '"${_escape('$value')}"';
  }

  static String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');

  static String? validate(String content) {
    try {
      TomlDocument.parse(content);
      return null;
    } on Object catch (error) {
      return '$error';
    }
  }
}
