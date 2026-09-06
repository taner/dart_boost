import 'package:dart_boost/src/guidelines/markdown_formatter.dart';
import 'package:test/test.dart';

void main() {
  test('collapses runs of blank lines', () {
    expect(MarkdownFormatter.format('a\n\n\n\n\nb'), 'a\n\nb\n');
  });

  test('puts a blank line around headings', () {
    expect(
      MarkdownFormatter.format('intro\n## Heading\nbody'),
      'intro\n\n## Heading\n\nbody\n',
    );
  });

  test('does not double an existing blank line around a heading', () {
    expect(
      MarkdownFormatter.format('intro\n\n## Heading\n\nbody'),
      'intro\n\n## Heading\n\nbody\n',
    );
  });

  // Boost's formatter runs its regexes unconditionally and happily rewrites
  // the inside of a code sample. Since the renderer already needs a fence
  // scanner, this one reuses it.
  test('leaves fenced code blocks alone', () {
    const source = 'text\n\n```sh\n# not a heading\n\n\n\nstill code\n```\n';
    expect(MarkdownFormatter.format(source), source);
  });

  test('normalizes line endings and guarantees one trailing newline', () {
    expect(MarkdownFormatter.format('a\r\nb\n\n\n'), 'a\nb\n');
    expect(MarkdownFormatter.format(''), '');
  });
}
