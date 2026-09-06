// Asserts that every file under `guidelines/` survives packaging.
//
// This is the only defence against the trap that would otherwise sink the
// first release: `dart pub publish` strips every dot-prefixed file and
// directory, so a fragment tree named `.ai/` (Boost's name) works perfectly in
// development and is *entirely absent* from the published archive. The tree is
// therefore not dot-prefixed -- and a stray `.gitignore` or `.pubignore` entry
// would reintroduce exactly the same failure silently.
//
// `dart pub publish --dry-run` prints the real file manifest, so this asks it.
//
// Usage: dart run tool/verify_assets.dart

import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main() async {
  final packageRoot = _packageRoot();
  final guidelines = Directory(p.join(packageRoot, 'guidelines'));

  if (!guidelines.existsSync()) {
    _fail('There is no guidelines/ directory at $packageRoot.');
  }

  final expected =
      guidelines
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (file) =>
                p.relative(file.path, from: packageRoot).replaceAll(r'\', '/'),
          )
          .toSet();

  if (expected.isEmpty) _fail('guidelines/ is empty; nothing to verify.');

  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'pub',
    'publish',
    '--dry-run',
  ], workingDirectory: packageRoot);

  // The dry run exits non-zero for unrelated reasons (a missing LICENSE, say),
  // and the manifest is printed either way -- so parse the output, do not gate
  // on the exit code.
  final manifest = _parseManifest('${result.stdout}\n${result.stderr}');

  if (manifest.isEmpty) {
    _fail(
      'Could not parse a file manifest out of `dart pub publish --dry-run`.\n'
      '--- output ---\n${result.stdout}\n${result.stderr}',
    );
  }

  final missing = expected.difference(manifest)..toList().sort();

  if (missing.isNotEmpty) {
    _fail(
      'These files exist on disk but would NOT be published:\n'
      '${missing.map((f) => '  - $f').join('\n')}\n\n'
      'Check .gitignore and .pubignore for an entry matching `guidelines`, and '
      'check that no path component is dot-prefixed.',
    );
  }

  stdout.writeln(
    'All ${expected.length} files under guidelines/ appear in the publish manifest.',
  );
}

/// Rebuilds full paths from pub's box-drawing tree.
///
/// ```
/// ├── guidelines
/// │   ├── dart
/// │   │   └── core.md (1 KB)
/// ```
Set<String> _parseManifest(String output) {
  final entry = RegExp(
    r'^([\s│├└─|`+\\-]*)(?:├──|└──|\|--|`--) (.+?)(?: \(.*\))?$',
  );
  final stack = <String>[];
  final files = <String>{};

  for (final line in output.split('\n')) {
    final match = entry.firstMatch(line.trimRight());
    if (match == null) continue;

    // Each level of the tree is four columns wide.
    final depth = match.group(1)!.length ~/ 4;
    final name = match.group(2)!.trim();
    if (name.isEmpty) continue;

    while (stack.length > depth) {
      stack.removeLast();
    }
    stack.add(name);

    // A size suffix marks a file; a bare name is a directory.
    if (line.contains(RegExp(r'\(<?\d+(\.\d+)? ?[KMG]?B\)$'))) {
      files.add(stack.join('/'));
    }
  }

  return files;
}

String _packageRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      _fail('No pubspec.yaml above ${Directory.current.path}');
    }
    dir = parent;
  }
}

Never _fail(String message) {
  stderr.writeln('verify_assets: $message');
  exit(1);
}
