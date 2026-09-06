@TestOn('vm')
library;

import 'package:test/test.dart';

import '../tool/verify_assets.dart';

/// A real `dart pub publish --dry-run` tree, trimmed. `pub` draws it with
/// box-drawing characters and marks files -- and only files -- with a size.
const _manifest = '''
Publishing dart_boost 0.1.0 to https://pub.dev:
├── CHANGELOG.md (<1 KB)
├── LICENSE (1 KB)
├── guidelines
│   ├── foundation.md (2 KB)
│   ├── dart
│   │   └── core.md (3 KB)
│   └── riverpod
│       ├── core.md (1 KB)
│       └── 3
│           ├── core.md (2 KB)
│           └── testing.md (1 KB)
└── lib
    └── dart_boost.dart (<1 KB)

Package has 1 warning.
''';

void main() {
  test('rebuilds full paths from the box-drawing tree', () {
    expect(parseManifest(_manifest), <String>{
      'CHANGELOG.md',
      'LICENSE',
      'guidelines/foundation.md',
      'guidelines/dart/core.md',
      'guidelines/riverpod/core.md',
      'guidelines/riverpod/3/core.md',
      'guidelines/riverpod/3/testing.md',
      'lib/dart_boost.dart',
    });
  });

  test('directories are not mistaken for files', () {
    // A bare name with no size suffix is a directory. If these leaked in, the
    // guard would compare a set of files against a set containing directories
    // and pass for the wrong reason.
    expect(parseManifest(_manifest), isNot(contains('guidelines')));
    expect(parseManifest(_manifest), isNot(contains('guidelines/dart')));
  });

  test('a CRLF manifest parses identically to an LF one', () {
    // `pub` writes CRLF on Windows. A `\r` left on the end of the line defeats
    // the `$`-anchored size probe, so every entry reads as a directory, the
    // manifest comes out empty, and the guard fails on the one platform whose
    // packaging quirks it exists to catch.
    final crlf = _manifest.replaceAll('\n', '\r\n');

    expect(parseManifest(crlf), parseManifest(_manifest));
    expect(parseManifest(crlf), isNotEmpty);
  });

  test('ASCII fallback drawing characters parse too', () {
    // `pub` falls back to `|--` / `` `-- `` where the terminal cannot render
    // box-drawing characters -- which is the default on a Windows runner.
    const ascii = '''
|-- guidelines
|   `-- dart
|       `-- core.md (3 KB)
`-- lib
    `-- dart_boost.dart (<1 KB)
''';

    expect(parseManifest(ascii), <String>{
      'guidelines/dart/core.md',
      'lib/dart_boost.dart',
    });
  });

  test('non-manifest output yields nothing rather than garbage', () {
    expect(parseManifest('Connection closed\nTry again.\n'), isEmpty);
  });
}
