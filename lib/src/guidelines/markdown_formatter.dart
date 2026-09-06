/// Normalization applied to composed output.
///
/// Boost's `MarkdownFormatter` does this with three unconditional regexes,
/// which happily rewrite the inside of a fenced code block. Since the renderer
/// already needs a fence scanner, this one skips fences -- a sample containing
/// two blank lines or a `# comment` line survives intact.
abstract final class MarkdownFormatter {
  static final _fence = RegExp(r'^(\s{0,3})(`{3,}|~{3,})(.*)$');
  static final _heading = RegExp(r'^#{1,4} \S');

  static String format(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final out = <String>[];

    String? fenceMarker;
    var fenceLength = 0;
    var blankRun = 0;

    void writeBlanks() {
      // Collapse any run of empty lines to a single blank line.
      if (blankRun > 0 && out.isNotEmpty) out.add('');
      blankRun = 0;
    }

    for (final line in lines) {
      if (fenceMarker != null) {
        out.add(line);
        final closer = _fence.firstMatch(line.trimRight());
        if (closer != null &&
            closer.group(2)![0] == fenceMarker &&
            closer.group(2)!.length >= fenceLength &&
            closer.group(3)!.trim().isEmpty) {
          fenceMarker = null;
          fenceLength = 0;
        }
        continue;
      }

      if (line.trim().isEmpty) {
        blankRun++;
        continue;
      }

      final opener = _fence.firstMatch(line.trimRight());
      final isHeading = opener == null && _heading.hasMatch(line);

      if (isHeading && blankRun == 0 && out.isNotEmpty) {
        // Ensure a blank line before a heading.
        out.add('');
      } else {
        writeBlanks();
      }
      blankRun = 0;

      out.add(line);

      if (opener != null) {
        fenceMarker = opener.group(2)![0];
        fenceLength = opener.group(2)!.length;
      } else if (isHeading) {
        // Ensure a blank line after a heading, without doubling up when the
        // source already had one.
        blankRun = 1;
      }
    }

    final result = out.join('\n').trimRight();
    return result.isEmpty ? '' : '$result\n';
  }
}
