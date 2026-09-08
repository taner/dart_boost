import 'package:yaml/yaml.dart';

/// One `.ai/rules/*.md` file: a `paths` frontmatter list plus a markdown body.
///
/// Parsing never throws. A rule file a human hand-edited into an invalid state
/// must not take down index regeneration -- it is skipped and reported, and
/// left on disk exactly as it was.
class RuleFile {
  const RuleFile({
    required this.path,
    required this.paths,
    required this.body,
    this.crlf = false,
  });

  /// Path on disk, as given to [parse].
  final String path;

  /// The globs this file's rules apply to.
  final List<String> paths;

  /// Everything after the frontmatter, trimmed.
  final String body;

  /// Whether the content [parse] was given used CRLF line endings. [render]
  /// restores them so appending a rule to a Windows-authored file does not
  /// rewrite every line in it -- the same whole-file git noise the
  /// deterministic index sorting exists to avoid.
  final bool crlf;

  /// The text after `# ` on the body's first line, or an empty string if the
  /// body does not start with a `# ` heading. Used by [render] and exposed
  /// for Task 3 to extract heading text without parsing the body twice.
  String get heading {
    final first = body.split('\n').first;
    return first.startsWith('# ') ? first.substring(2).trim() : '';
  }

  /// The body with the first heading line removed and trimmed. If the body does
  /// not start with a `# ` heading line, returns the whole body. Used by
  /// [render] and exposed for Task 3 to avoid duplicating this logic.
  String get bodyWithoutHeading {
    final lines = body.split('\n');
    if (lines.isEmpty || !lines.first.startsWith('# ')) return body;
    return lines.skip(1).join('\n').trim();
  }

  static RuleFile? parse(String path, String content) {
    final crlf = content.contains('\r\n');
    final normalized = content.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) return null;

    final end = normalized.indexOf('\n---', 3);
    if (end == -1) return null;

    // Find the end of the closing delimiter line.
    // After '\n---', there might be more dashes, then a newline or end of string.
    int delimEnd = end + 4; // Position after '\n---'
    while (delimEnd < normalized.length && normalized[delimEnd] == '-') {
      delimEnd++;
    }

    // Verify we're at a newline or end of string (no other characters)
    if (delimEnd < normalized.length && normalized[delimEnd] != '\n') {
      return null; // Invalid delimiter: has non-dash characters
    }

    // Skip the newline if present
    if (delimEnd < normalized.length && normalized[delimEnd] == '\n') {
      delimEnd++;
    }

    final frontmatter = normalized.substring(4, end + 1);
    final body = normalized.substring(delimEnd).trim();

    final Object? parsed;
    try {
      parsed = loadYaml(frontmatter);
    } on Object {
      return null;
    }

    if (parsed is! Map) return null;
    final paths = parsed['paths'];
    if (paths is! List) return null;

    final globs =
        paths
            .whereType<String>()
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toList();
    if (globs.isEmpty) return null;

    return RuleFile(path: path, paths: globs, body: body, crlf: crlf);
  }

  String render() {
    final rendered = renderRuleFile(
      paths: paths,
      heading: heading,
      body: bodyWithoutHeading,
    );
    return crlf ? rendered.replaceAll('\n', '\r\n') : rendered;
  }
}

/// Renders a rule file. Always ends with a single trailing newline.
String renderRuleFile({
  required List<String> paths,
  required String heading,
  required String body,
}) {
  final buffer = StringBuffer('---\npaths:\n');
  for (final glob in paths) {
    buffer.writeln('  - $glob');
  }
  buffer.writeln('---');
  buffer.writeln();
  if (heading.isNotEmpty) {
    buffer.writeln('# $heading');
    buffer.writeln();
  }
  buffer.writeln(body.trim());
  return buffer.toString();
}
