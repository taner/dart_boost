# Project Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give dart_boost glob-scoped project rules -- an MCP tool that records a
team's own decisions mid-session, and a bundled procedure that bootstraps them
from an existing codebase.

**Architecture:** A pure `RuleRepository` writes `.ai/rules/*.md` and regenerates
a glob index; a single-tool MCP server (`dart run dart_boost:mcp`) is a thin
adapter over it, so `package:dart_mcp` is confined to one file. `infer-conventions`
ships as a markdown procedure rather than a tool, because it runs once per project
and would otherwise cost tool-list context in every session forever.

**Tech Stack:** Dart 3.7+, `package:dart_mcp` (labs.dart.dev), `package:file`
FileSystem abstraction, `package:yaml`, `package:glob`, `package:test` +
`test_descriptor`.

**Spec:** `docs/superpowers/specs/2026-09-07-project-rules-design.md`

## Global Constraints

- **SDK floor is `^3.7.0`.** `package:dart_mcp` matches it exactly. Do not raise it.
- **Never dot-prefix a bundled asset.** `dart pub publish` strips every
  dot-prefixed file and directory, so a `.ai/` tree in *this* package would work
  locally and be absent from the release. Bundled assets live in `guidelines/`
  and `assets/`. Dot-prefixed paths are fine in the *target* project.
- **Nothing throws.** A malformed input degrades with a warning; it never aborts
  an install and never crashes the MCP server.
- **Every user-file write goes through `AtomicWriter`** (temp file + rename, one
  `.dart-boost.bak`).
- **Tests are hermetic:** no network, no subprocesses except through
  `FakeProcessRunner`. Unit tests use `MemoryFileSystem`; CLI tests use
  `test_descriptor` on a real filesystem.
- **CRLF must round-trip.** Fixtures are pinned `-text` in `.gitattributes`.
- **Style gate:** `dart format .` clean and `dart analyze --fatal-infos` clean
  before every commit.
- **Rules default to enabled**, but the dev dependency is never added unasked:
  under `--yes` or CI with dart_boost absent from the pubspec, rules wiring is
  skipped and reported.

---

### Task 1: Rule file model and frontmatter

**Files:**
- Create: `lib/src/rules/rule_file.dart`
- Test: `test/rules/rule_file_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class RuleFile { final String path; final List<String> paths; final String body; static RuleFile? parse(String path, String content); String render(); }`
  and `String renderRuleFile({required List<String> paths, required String heading, required String body})`.
  `parse` returns `null` for content with no valid `paths` frontmatter.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/rule_file_test.dart
@TestOn('vm')
library;

import 'package:dart_boost/src/rules/rule_file.dart';
import 'package:test/test.dart';

void main() {
  group('RuleFile.parse', () {
    test('reads the paths list and keeps the body verbatim', () {
      const content = '''
---
paths:
  - lib/models/**
  - lib/entities/**
---

# Models

## Money is integer cents

Use `int` cents.
''';

      final file = RuleFile.parse('.ai/rules/models.md', content)!;

      expect(file.paths, <String>['lib/models/**', 'lib/entities/**']);
      expect(file.body, contains('## Money is integer cents'));
      expect(file.body, startsWith('# Models'));
    });

    test('returns null when there is no frontmatter', () {
      expect(RuleFile.parse('x.md', '# Just a heading\n'), isNull);
    });

    test('returns null when frontmatter has no paths key', () {
      expect(RuleFile.parse('x.md', '---\ntitle: nope\n---\n\nbody\n'), isNull);
    });

    test('returns null rather than throwing on malformed yaml', () {
      expect(RuleFile.parse('x.md', '---\npaths: [unclosed\n---\n\nbody\n'), isNull);
    });

    test('round-trips CRLF content without corrupting it', () {
      const content = '---\r\npaths:\r\n  - test/**\r\n---\r\n\r\n# Testing\r\n';
      final file = RuleFile.parse('.ai/rules/test.md', content)!;

      expect(file.paths, <String>['test/**']);
      expect(file.body, '# Testing');
    });
  });

  group('renderRuleFile', () {
    test('emits frontmatter, heading and body', () {
      final out = renderRuleFile(
        paths: <String>['lib/models/**'],
        heading: 'Models',
        body: '## Money is integer cents\n\nUse `int` cents.',
      );

      expect(out, '''
---
paths:
  - lib/models/**
---

# Models

## Money is integer cents

Use `int` cents.
''');
    });

    test('parse and render round-trip', () {
      final rendered = renderRuleFile(
        paths: <String>['test/**'],
        heading: 'Test',
        body: '## Always use group()\n\nGroup related tests.',
      );

      final parsed = RuleFile.parse('.ai/rules/test.md', rendered)!;

      expect(parsed.paths, <String>['test/**']);
      expect(renderRuleFile(
        paths: parsed.paths,
        heading: 'Test',
        body: parsed.body.split('\n').skip(2).join('\n').trim(),
      ), rendered);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/rule_file_test.dart`
Expected: FAIL -- `Error: Couldn't resolve the package 'dart_boost' ... rule_file.dart` (the file does not exist).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/rules/rule_file.dart
import 'package:yaml/yaml.dart';

/// One `.ai/rules/*.md` file: a `paths` frontmatter list plus a markdown body.
///
/// Parsing never throws. A rule file a human hand-edited into an invalid state
/// must not take down index regeneration -- it is skipped and reported, and
/// left on disk exactly as it was.
class RuleFile {
  const RuleFile({required this.path, required this.paths, required this.body});

  /// Path on disk, as given to [parse].
  final String path;

  /// The globs this file's rules apply to.
  final List<String> paths;

  /// Everything after the frontmatter, trimmed.
  final String body;

  static RuleFile? parse(String path, String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) return null;

    final end = normalized.indexOf('\n---', 3);
    if (end == -1) return null;

    final frontmatter = normalized.substring(4, end + 1);
    final body = normalized.substring(end + 4).trim();

    final Object? parsed;
    try {
      parsed = loadYaml(frontmatter);
    } on Object {
      return null;
    }

    if (parsed is! Map) return null;
    final paths = parsed['paths'];
    if (paths is! List) return null;

    final globs = paths.whereType<String>().map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
    if (globs.isEmpty) return null;

    return RuleFile(path: path, paths: globs, body: body);
  }

  String render() => renderRuleFile(
    paths: paths,
    heading: _headingOf(body),
    body: _afterHeading(body),
  );

  static String _headingOf(String body) {
    final first = body.split('\n').first;
    return first.startsWith('# ') ? first.substring(2).trim() : '';
  }

  static String _afterHeading(String body) {
    final lines = body.split('\n');
    if (lines.isEmpty || !lines.first.startsWith('# ')) return body;
    return lines.skip(1).join('\n').trim();
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/rules/rule_file_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos
git add lib/src/rules/rule_file.dart test/rules/rule_file_test.dart
git commit -m "Add the rule file model and its frontmatter parser"
```

---

### Task 2: Glob normalization and area routing

**Files:**
- Create: `lib/src/rules/rule_area.dart`
- Test: `test/rules/rule_area_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  `List<String> meaningfulSegments(String glob)`,
  `String areaKey(String glob)`,
  `List<String> filenameCandidates(String glob)` (slug candidates, shortest first, always non-empty -- falls back to `['general']`),
  `String? normalizeGlob(String glob, {required String projectRoot})` returning `null` when the glob escapes the root.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/rule_area_test.dart
@TestOn('vm')
library;

import 'package:dart_boost/src/rules/rule_area.dart';
import 'package:test/test.dart';

void main() {
  group('meaningfulSegments', () {
    test('drops wildcard and dotted segments', () {
      expect(meaningfulSegments('lib/models/**'), <String>['lib', 'models']);
      expect(meaningfulSegments('test/**/*_test.dart'), <String>['test']);
      expect(meaningfulSegments('lib/models/*.dart'), <String>['lib', 'models']);
      expect(meaningfulSegments('**'), isEmpty);
    });
  });

  group('areaKey', () {
    test('two globs over the same directory share an area', () {
      expect(areaKey('lib/models/**'), areaKey('lib/models/*.dart'));
    });

    test('different directories do not share an area', () {
      expect(areaKey('lib/models/**'), isNot(areaKey('lib/widgets/**')));
    });
  });

  group('filenameCandidates', () {
    test('offers the shortest slug first, then widens', () {
      expect(
        filenameCandidates('lib/src/widgets/**'),
        <String>['widgets', 'src-widgets', 'lib-src-widgets'],
      );
    });

    test('falls back to general when nothing is meaningful', () {
      expect(filenameCandidates('**'), <String>['general']);
    });

    test('slugs are lowercase and hyphenated', () {
      expect(filenameCandidates('lib/DataSources/**').first, 'datasources');
    });
  });

  group('normalizeGlob', () {
    test('makes an absolute path relative to the project root', () {
      expect(
        normalizeGlob('/home/me/app/lib/models/**', projectRoot: '/home/me/app'),
        'lib/models/**',
      );
    });

    test('converts backslashes and strips a leading slash', () {
      expect(normalizeGlob(r'lib\models\**', projectRoot: '/app'), 'lib/models/**');
      expect(normalizeGlob('/lib/models/**', projectRoot: '/app'), 'lib/models/**');
    });

    test('rejects a glob that escapes the project root', () {
      expect(normalizeGlob('../other/**', projectRoot: '/app'), isNull);
      expect(normalizeGlob('lib/../../escape/**', projectRoot: '/app'), isNull);
    });

    test('rejects an empty glob', () {
      expect(normalizeGlob('   ', projectRoot: '/app'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/rule_area_test.dart`
Expected: FAIL -- `rule_area.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/rules/rule_area.dart
import 'package:path/path.dart' as p;

/// Segments of a glob that name a real directory: no wildcards, no dots.
///
/// `lib/models/**` -> `[lib, models]`. This is what decides which rules belong
/// together, so it deliberately ignores the wildcard tail: a rule about
/// `lib/models/**` and one about `lib/models/*.dart` are about the same place.
List<String> meaningfulSegments(String glob) => glob
    .split('/')
    .where((s) => s.isNotEmpty && !s.contains('*') && !s.contains('.'))
    .toList();

/// Two globs with the same area key are filed together.
String areaKey(String glob) => meaningfulSegments(glob).join('/');

/// Slug candidates for a new rule file, shortest first.
///
/// `lib/src/widgets/**` offers `widgets`, then `src-widgets`, then
/// `lib-src-widgets`. The caller takes the first that is not already in use,
/// so a file gets the shortest name that stays unambiguous.
List<String> filenameCandidates(String glob) {
  final segments = meaningfulSegments(glob);
  if (segments.isEmpty) return <String>['general'];

  return <String>[
    for (var take = 1; take <= segments.length; take++)
      _slug(segments.sublist(segments.length - take)),
  ];
}

String _slug(List<String> segments) => segments
    .join('-')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Project-relative, forward-slashed, and inside the project.
///
/// Returns `null` for a glob that escapes the root: rules describe *this*
/// project, and a rule filed against `../` would be unreachable from the index.
String? normalizeGlob(String glob, {required String projectRoot}) {
  var value = glob.trim().replaceAll(r'\', '/');
  if (value.isEmpty) return null;

  final root = '${projectRoot.replaceAll(r'\', '/')}/';
  if (value.startsWith(root)) value = value.substring(root.length);

  value = value.replaceAll(RegExp('^/+'), '');
  if (value.isEmpty) return null;

  // Resolve `..` against a virtual root; anything that climbs out is refused.
  final wildcard = value.contains('*');
  final probe = wildcard ? value.replaceAll(RegExp(r'[*?]+'), 'x') : value;
  final resolved = p.posix.normalize(probe);
  if (resolved.startsWith('..') || p.posix.isAbsolute(resolved)) return null;

  return value;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/rules/rule_area_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos
git add lib/src/rules/rule_area.dart test/rules/rule_area_test.dart
git commit -m "Add glob normalization and area routing for project rules"
```

---

### Task 3: RuleRepository -- write a rule, regenerate the index

**Files:**
- Create: `lib/src/rules/rule_repository.dart`
- Test: `test/rules/rule_repository_test.dart`

**Interfaces:**
- Consumes: `RuleFile`, `renderRuleFile` (Task 1); `areaKey`, `filenameCandidates`, `normalizeGlob` (Task 2); `AtomicWriter` from `lib/src/writers/atomic_writer.dart`.
- Produces:
  `class RuleWriteResult { final String path; final bool created; }`,
  `class RuleRepository { RuleRepository({required FileSystem fileSystem, required Directory projectRoot, bool dryRun = false}); String get directory; String get indexPath; RuleWriteResult write({required String glob, required String title, required String note}); List<RuleFile> readAll({void Function(String)? onWarning}); bool writeIndex({void Function(String)? onWarning}); }`.
  `write` throws `ArgumentError` only for an un-normalizable glob; callers validate first.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/rule_repository_test.dart
@TestOn('vm')
library;

import 'package:dart_boost/src/rules/rule_repository.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  late RuleRepository repo;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/app').createSync(recursive: true);
    repo = RuleRepository(fileSystem: fs, projectRoot: fs.directory('/app'));
  });

  String read(String path) => fs.file(path).readAsStringSync();

  test('creates a rule file named for the shortest unambiguous slug', () {
    final result = repo.write(
      glob: 'lib/models/**',
      title: 'Money is integer cents',
      note: 'Use `int` cents, never `double`.',
    );

    expect(result.path, '/app/.ai/rules/models.md');
    expect(result.created, isTrue);
    expect(read(result.path), contains('paths:\n  - lib/models/**'));
    expect(read(result.path), contains('## Money is integer cents'));
    expect(read(result.path), contains('Use `int` cents, never `double`.'));
  });

  test('appends a second rule in the same area to the same file', () {
    repo.write(glob: 'lib/models/**', title: 'First', note: 'One.');
    final second = repo.write(glob: 'lib/models/*.dart', title: 'Second', note: 'Two.');

    expect(second.path, '/app/.ai/rules/models.md');
    expect(second.created, isFalse);

    final content = read(second.path);
    expect(content, contains('## First'));
    expect(content, contains('## Second'));
    expect(content, contains('  - lib/models/**'));
    expect(content, contains('  - lib/models/*.dart'));
    expect(fs.directory('/app/.ai/rules').listSync().whereType<File>().length, 2); // rule + index
  });

  test('a different area gets its own file', () {
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    final other = repo.write(glob: 'lib/widgets/**', title: 'B', note: 'b');

    expect(other.path, '/app/.ai/rules/widgets.md');
  });

  test('widens the slug when the short name is taken by another area', () {
    repo.write(glob: 'lib/widgets/**', title: 'A', note: 'a');
    final other = repo.write(glob: 'packages/ui/widgets/**', title: 'B', note: 'b');

    expect(other.path, '/app/.ai/rules/ui-widgets.md');
  });

  test('regenerates the index with every glob', () {
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo.write(glob: 'test/**', title: 'B', note: 'b');

    final index = read('/app/.ai/rules/index.md');
    expect(index, contains('# Project Rules Index'));
    expect(index, contains('| `lib/models/**` | `.ai/rules/models.md` |'));
    expect(index, contains('| `test/**` | `.ai/rules/test.md` |'));
  });

  test('index ordering is deterministic regardless of write order', () {
    repo.write(glob: 'test/**', title: 'B', note: 'b');
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    final first = read('/app/.ai/rules/index.md');

    final fs2 = MemoryFileSystem.test()..directory('/app').createSync(recursive: true);
    final repo2 = RuleRepository(fileSystem: fs2, projectRoot: fs2.directory('/app'));
    repo2.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo2.write(glob: 'test/**', title: 'B', note: 'b');

    expect(fs2.file('/app/.ai/rules/index.md').readAsStringSync(), first);
  });

  test('a malformed rule file is skipped, warned about, and left on disk', () {
    fs.directory('/app/.ai/rules').createSync(recursive: true);
    fs.file('/app/.ai/rules/broken.md').writeAsStringSync('no frontmatter here\n');

    final warnings = <String>[];
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo.writeIndex(onWarning: warnings.add);

    expect(warnings.single, contains('broken.md'));
    expect(fs.file('/app/.ai/rules/broken.md').readAsStringSync(), 'no frontmatter here\n');
    expect(read('/app/.ai/rules/index.md'), isNot(contains('broken.md')));
  });

  test('writing the same rule twice does not duplicate the glob', () {
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo.write(glob: 'lib/models/**', title: 'B', note: 'b');

    final content = read('/app/.ai/rules/models.md');
    expect('  - lib/models/**'.allMatches(content).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/rule_repository_test.dart`
Expected: FAIL -- `rule_repository.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/rules/rule_repository.dart
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../writers/atomic_writer.dart';
import 'rule_area.dart';
import 'rule_file.dart';

class RuleWriteResult {
  const RuleWriteResult({required this.path, required this.created});

  final String path;
  final bool created;
}

/// Reads and writes `.ai/rules/`.
///
/// Knows nothing about MCP. The server is a thin adapter over this, so an
/// upstream break in `package:dart_mcp` cannot reach the rules themselves.
class RuleRepository {
  RuleRepository({
    required this.fileSystem,
    required this.projectRoot,
    this.dryRun = false,
  });

  final FileSystem fileSystem;
  final Directory projectRoot;
  final bool dryRun;

  static const relativeDirectory = '.ai/rules';
  static const indexFileName = 'index.md';

  String get directory =>
      p.join(projectRoot.path, p.joinAll(relativeDirectory.split('/')));

  String get indexPath => p.join(directory, indexFileName);

  RuleWriteResult write({
    required String glob,
    required String title,
    required String note,
  }) {
    final normalized = normalizeGlob(glob, projectRoot: projectRoot.path);
    if (normalized == null) {
      throw ArgumentError.value(glob, 'glob', 'outside the project root');
    }

    final cleanTitle = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final cleanNote = note.trim();

    final existing = readAll();
    final target = _resolveTarget(normalized, existing);

    final String content;
    if (target.file == null) {
      content = renderRuleFile(
        paths: <String>[normalized],
        heading: _headingFor(target.path),
        body: '## $cleanTitle\n\n$cleanNote',
      );
    } else {
      final current = target.file!;
      final paths = <String>[
        ...current.paths,
        if (!current.paths.contains(normalized)) normalized,
      ];
      content = renderRuleFile(
        paths: paths,
        heading: _headingOf(current.body),
        body: '${_afterHeading(current.body)}\n\n## $cleanTitle\n\n$cleanNote'.trim(),
      );
    }

    _write(target.path, content);
    writeIndex();

    return RuleWriteResult(path: target.path, created: target.file == null);
  }

  List<RuleFile> readAll({void Function(String)? onWarning}) {
    final dir = fileSystem.directory(directory);
    if (!dir.existsSync()) return <RuleFile>[];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.md')
        .where((f) => p.basename(f.path) != indexFileName)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final parsed = <RuleFile>[];
    for (final file in files) {
      final rule = RuleFile.parse(file.path, file.readAsStringSync());
      if (rule == null) {
        onWarning?.call(
          'Skipping ${p.basename(file.path)}: no valid `paths` frontmatter. '
          'The file was left untouched.',
        );
        continue;
      }
      parsed.add(rule);
    }
    return parsed;
  }

  /// Rebuilds `index.md` from whatever is on disk. Returns whether it changed.
  bool writeIndex({void Function(String)? onWarning}) {
    final rules = readAll(onWarning: onWarning);

    final rows = <({String glob, String file})>[
      for (final rule in rules)
        for (final glob in rule.paths)
          (glob: glob, file: _relative(rule.path)),
    ]..sort((a, b) {
        final byFile = a.file.compareTo(b.file);
        return byFile != 0 ? byFile : a.glob.compareTo(b.glob);
      });

    final buffer = StringBuffer()
      ..writeln('# Project Rules Index')
      ..writeln()
      ..writeln(
        'Before planning or editing a file, find the row whose globs match its '
        'path and read that rule file.',
      )
      ..writeln()
      ..writeln('| Applies to | Rule file |')
      ..writeln('| --- | --- |');

    for (final row in rows) {
      buffer.writeln('| `${row.glob}` | `${row.file}` |');
    }

    return _write(indexPath, buffer.toString());
  }

  ({String path, RuleFile? file}) _resolveTarget(
    String glob,
    List<RuleFile> existing,
  ) {
    final area = areaKey(glob);

    for (final rule in existing) {
      final matches = rule.paths.contains(glob) ||
          rule.paths.any((existing) => areaKey(existing) == area);
      if (matches) return (path: rule.path, file: rule);
    }

    final taken = existing.map((r) => p.basename(r.path)).toSet();
    for (final candidate in filenameCandidates(glob)) {
      final name = '$candidate.md';
      if (name == indexFileName || taken.contains(name)) continue;
      if (fileSystem.file(p.join(directory, name)).existsSync()) continue;
      return (path: p.join(directory, name), file: null);
    }

    final base = filenameCandidates(glob).last;
    var suffix = 2;
    while (true) {
      final name = '$base-$suffix.md';
      if (!taken.contains(name) &&
          !fileSystem.file(p.join(directory, name)).existsSync()) {
        return (path: p.join(directory, name), file: null);
      }
      suffix++;
    }
  }

  bool _write(String path, String content) {
    fileSystem.directory(p.dirname(path)).createSync(recursive: true);
    return AtomicWriter(fileSystem, dryRun: dryRun)
        .write(path, content, backup: false);
  }

  String _relative(String path) =>
      p.relative(path, from: projectRoot.path).replaceAll(r'\', '/');

  static String _headingFor(String path) {
    final base = p.basenameWithoutExtension(path);
    return base
        .split('-')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _headingOf(String body) {
    final first = body.split('\n').first;
    return first.startsWith('# ') ? first.substring(2).trim() : '';
  }

  static String _afterHeading(String body) {
    final lines = body.split('\n');
    if (lines.isEmpty || !lines.first.startsWith('# ')) return body;
    return lines.skip(1).join('\n').trim();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/rules/rule_repository_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos
git add lib/src/rules/rule_repository.dart test/rules/rule_repository_test.dart
git commit -m "Add RuleRepository: write rules, regenerate the glob index"
```

---

### Task 4: `dart run dart_boost rules index`

**Files:**
- Create: `lib/src/cli/commands/rules_command.dart`
- Modify: `lib/src/cli/runner.dart` (register the command alongside the existing four)
- Test: `test/rules/rules_command_test.dart`

**Interfaces:**
- Consumes: `RuleRepository` (Task 3); the existing `BoostCommand` base in `lib/src/cli/commands/boost_command.dart` and `CliContext` in `lib/src/cli/context.dart`.
- Produces: `class RulesCommand extends Command<int>` with subcommand `index`, registered under name `rules`.

- [ ] **Step 1: Read the existing command shape**

Run: `sed -n '1,60p' lib/src/cli/commands/doctor_command.dart && sed -n '1,80p' lib/src/cli/runner.dart`
Mirror that constructor signature, context plumbing and exit-code convention exactly rather than inventing a new one.

- [ ] **Step 2: Write the failing test**

```dart
// test/rules/rules_command_test.dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('rules index rebuilds the index from a hand-added rule file', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[
          d.file('models.md', '---\npaths:\n  - lib/models/**\n---\n\n# Models\n\n## A\n\na\n'),
        ]),
      ]),
    ]).create();

    final result = await runCli(<String>['rules', 'index', '-C', d.path('app')]);

    expect(result.exitCode, 0);
    await d.dir('app', <d.Descriptor>[
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[
          d.file('index.md', contains('| `lib/models/**` | `.ai/rules/models.md` |')),
        ]),
      ]),
    ]).validate();
  });

  test('rules index reports a malformed file without failing', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[d.file('broken.md', 'nope\n')]),
      ]),
    ]).create();

    final result = await runCli(<String>['rules', 'index', '-C', d.path('app')]);

    expect(result.exitCode, 0);
    expect(result.output, contains('broken.md'));
  });
}
```

If `test/support/cli_harness.dart` does not already expose a `runCli` helper,
reuse whatever `test/install_integration_test.dart` uses to drive the runner and
capture output, and add the helper there rather than duplicating it.

- [ ] **Step 3: Run test to verify it fails**

Run: `dart test test/rules/rules_command_test.dart`
Expected: FAIL -- `Could not find a command named "rules"`.

- [ ] **Step 4: Write minimal implementation**

```dart
// lib/src/cli/commands/rules_command.dart
import 'package:args/command_runner.dart';

import '../../rules/rule_repository.dart';
import '../context.dart';

/// `dart run dart_boost rules index`.
///
/// The index is regenerated on every `record_rule`, so this exists for the one
/// case that bypasses the tool: a rule file added or edited by hand, which is
/// invisible to agents until the index names it.
class RulesCommand extends Command<int> {
  RulesCommand(this.context) {
    addSubcommand(_RulesIndexCommand(context));
  }

  final CliContext context;

  @override
  String get name => 'rules';

  @override
  String get description => 'Inspect and maintain .ai/rules.';
}

class _RulesIndexCommand extends Command<int> {
  _RulesIndexCommand(this.context);

  final CliContext context;

  @override
  String get name => 'index';

  @override
  String get description => 'Regenerate .ai/rules/index.md from the rule files on disk.';

  @override
  int run() {
    final root = context.projectRoot;
    final repository = RuleRepository(
      fileSystem: context.fileSystem,
      projectRoot: root,
    );

    final changed = repository.writeIndex(onWarning: context.logger.warn);
    context.logger.info(
      changed
          ? 'Rewrote ${repository.indexPath}.'
          : 'Index already up to date.',
    );
    return 0;
  }
}
```

Adjust `context.projectRoot`, `context.fileSystem` and `context.logger` to the
real member names on `CliContext` as read in Step 1.

- [ ] **Step 5: Register the command**

In `lib/src/cli/runner.dart`, add `RulesCommand(context)` next to the existing
`addCommand(...)` calls, with the matching import.

- [ ] **Step 6: Run test to verify it passes**

Run: `dart test test/rules/rules_command_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos && dart test
git add lib/src/cli/commands/rules_command.dart lib/src/cli/runner.dart test/rules/rules_command_test.dart test/support/
git commit -m "Add `rules index` to regenerate the rule index by hand"
```

---

### Task 5: Split state into committed choices and per-machine observations

**Files:**
- Modify: `lib/src/state/boost_state.dart` (drop `dependencies`, `fragments`, `lastRun`; add `rules`; bump `currentSchemaVersion` to 2; migrate)
- Create: `lib/src/state/machine_state.dart`
- Modify: `lib/src/install/dependency_drift.dart` (read/write the new store), `lib/src/cli/commands/install_command.dart`, `lib/src/cli/commands/update_command.dart`
- Test: `test/state_test.dart` (extend), `test/state_migration_test.dart` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  `BoostState` gains `final RulesSettings rules;` where
  `class RulesSettings { const RulesSettings({this.enabled = true}); final bool enabled; Map<String, Object?> toJson(); static RulesSettings fromJson(Object?); }`.
  `class MachineState { const MachineState({this.dependencies, this.fragments, this.lastRun}); ... }` with the same nullable semantics `BoostState` had, and
  `class MachineStateStore { const MachineStateStore(FileSystem, Directory projectRoot); static const relativePath = '.dart_tool/dart_boost/state.json'; File get file; MachineState? read({void Function(String)? onWarning}); void write(MachineState); }`.
  `BoostStateStore.read` returns a record `({BoostState state, MachineState? migrated})` so a v1 file's observations survive the split.

- [ ] **Step 1: Write the failing migration test**

```dart
// test/state_migration_test.dart
@TestOn('vm')
library;

import 'dart:convert';

import 'package:dart_boost/src/state/boost_state.dart';
import 'package:dart_boost/src/state/machine_state.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/app').createSync(recursive: true);
  });

  void writeV1(Map<String, Object?> json) => fs
      .file('/app/dart_boost.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

  test('a v1 file splits into v2 choices plus machine state', () {
    writeV1(<String, Object?>{
      'version': 1,
      'agents': <String>['claude_code'],
      'features': <String, Object?>{'guidelines': true, 'mcp': true},
      'thirdPartyPackages': <String>['serverpod'],
      'delegateSkills': false,
      'dependencies': <String, Object?>{'go_router': '18.2.0'},
      'fragments': <String>['foundation'],
      'lastRun': <String, Object?>{'flutter': '3.47.2', 'dart': '3.13.2'},
    });

    final store = BoostStateStore(fs, fs.directory('/app'));
    final result = store.read()!;

    expect(result.state.schemaVersion, 2);
    expect(result.state.agents, <String>['claude_code']);
    expect(result.state.thirdPartyPackages, <String>['serverpod']);
    expect(result.state.rules.enabled, isTrue);

    expect(result.migrated, isNotNull);
    expect(result.migrated!.dependencies, <String, String>{'go_router': '18.2.0'});
    expect(result.migrated!.fragments, <String>['foundation']);
    expect(result.migrated!.lastRun!.flutter, '3.47.2');
  });

  test('a v1 file without dependencies keeps null, not empty', () {
    writeV1(<String, Object?>{
      'version': 1,
      'agents': <String>['claude_code'],
      'features': <String, Object?>{'guidelines': true, 'mcp': true},
    });

    final result = BoostStateStore(fs, fs.directory('/app')).read()!;

    expect(result.migrated?.dependencies, isNull);
    expect(result.migrated?.fragments, isNull);
  });

  test('a v2 file reports no migration', () {
    writeV1(<String, Object?>{
      'version': 2,
      'agents': <String>['claude_code'],
      'features': <String, Object?>{'guidelines': true, 'mcp': true},
      'rules': <String, Object?>{'enabled': false},
    });

    final result = BoostStateStore(fs, fs.directory('/app')).read()!;

    expect(result.migrated, isNull);
    expect(result.state.rules.enabled, isFalse);
  });

  test('v2 choices carry no observation keys', () {
    final rendered = BoostStateStore.render(
      BoostState(agents: <String>['claude_code']),
    );

    expect(rendered, isNot(contains('dependencies')));
    expect(rendered, isNot(contains('lastRun')));
    expect(rendered, contains('"rules"'));
  });

  test('machine state round-trips through its own store', () {
    final store = MachineStateStore(fs, fs.directory('/app'));
    store.write(const MachineState(
      dependencies: <String, String>{'dio': '5.11.1'},
      fragments: <String>['dio/core'],
      lastRun: LastRun(flutter: '3.47.2'),
    ));

    expect(store.file.path, '/app/.dart_tool/dart_boost/state.json');
    expect(store.read()!.dependencies, <String, String>{'dio': '5.11.1'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/state_migration_test.dart`
Expected: FAIL -- `machine_state.dart` does not exist and `read()` returns `BoostState?`.

- [ ] **Step 3: Create `machine_state.dart`**

Move `LastRun` out of `boost_state.dart` into `machine_state.dart` verbatim, and
add beside it:

```dart
// lib/src/state/machine_state.dart
import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// What the last run *observed*, as opposed to what the user *chose*.
///
/// Lives under `.dart_tool/`, which every Dart project already gitignores,
/// because these values differ per machine. Committing them made every
/// teammate on a different SDK rewrite the file, and made `update` diff your
/// project against whoever last committed rather than against your own last
/// run.
class MachineState {
  const MachineState({this.dependencies, this.fragments, this.lastRun});

  static const currentSchemaVersion = 2;

  /// `null` -- not the empty map -- means the last run predates this field.
  /// An empty map means "a project with no dependencies", and conflating the
  /// two makes `update` announce every existing dependency as newly added.
  final Map<String, String>? dependencies;

  final List<String>? fragments;

  final LastRun? lastRun;

  MachineState copyWith({
    Map<String, String>? dependencies,
    List<String>? fragments,
    LastRun? lastRun,
  }) => MachineState(
    dependencies: dependencies ?? this.dependencies,
    fragments: fragments ?? this.fragments,
    lastRun: lastRun ?? this.lastRun,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentSchemaVersion,
    if (dependencies != null) 'dependencies': dependencies,
    if (fragments != null) 'fragments': fragments,
    if (lastRun != null) 'lastRun': lastRun!.toJson(),
  };

  static MachineState fromJson(Map<String, Object?> json) => MachineState(
    dependencies:
        json.containsKey('dependencies') ? _stringMap(json['dependencies']) : null,
    fragments: json.containsKey('fragments') ? _strings(json['fragments']) : null,
    lastRun: json['lastRun'] is Map<String, Object?>
        ? LastRun.fromJson(json['lastRun']! as Map<String, Object?>)
        : null,
  );

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : <String>[];

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    return <String, String>{
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }
}

/// Lets `update` say "Flutter 3.44 -> 3.47, re-composing".
class LastRun {
  const LastRun({this.flutter, this.dart, this.boostVersion});

  final String? flutter;
  final String? dart;
  final String? boostVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    if (flutter != null) 'flutter': flutter,
    if (dart != null) 'dart': dart,
    if (boostVersion != null) 'boostVersion': boostVersion,
  };

  static LastRun fromJson(Map<String, Object?> json) => LastRun(
    flutter: json['flutter'] as String?,
    dart: json['dart'] as String?,
    boostVersion: json['boostVersion'] as String?,
  );
}

class MachineStateStore {
  const MachineStateStore(this.fileSystem, this.projectRoot);

  static const relativePath = '.dart_tool/dart_boost/state.json';

  final FileSystem fileSystem;
  final Directory projectRoot;

  File get file =>
      fileSystem.file(p.join(projectRoot.path, p.joinAll(relativePath.split('/'))));

  bool get exists => file.existsSync();

  MachineState? read({void Function(String)? onWarning}) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      return MachineState.fromJson(decoded);
    } on Object catch (error) {
      onWarning?.call('Ignoring unreadable ${file.path}: $error');
      return null;
    }
  }

  void write(MachineState state) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(state.toJson())}\n',
    );
  }
}
```

- [ ] **Step 4: Reduce `boost_state.dart` to choices**

Remove `dependencies`, `fragments`, `lastRun` and the `LastRun` class from
`boost_state.dart`; import `LastRun` from `machine_state.dart` where still
referenced. Set `currentSchemaVersion = 2`. Add:

```dart
class RulesSettings {
  const RulesSettings({this.enabled = true});

  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{'enabled': enabled};

  static RulesSettings fromJson(Object? value) {
    if (value is! Map) return const RulesSettings();
    return RulesSettings(enabled: value['enabled'] as bool? ?? true);
  }
}
```

Add `final RulesSettings rules;` (defaulting to `const RulesSettings()`), thread
it through the constructor, `copyWith` and `toJson`/`fromJson`, and change
`BoostStateStore.read` to:

```dart
  /// Returns the choices plus, for a v1 file, the observations that used to
  /// live alongside them so the caller can write them to their new home.
  ({BoostState state, MachineState? migrated})? read({
    void Function(String)? onWarning,
  }) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;

      final version = (decoded['version'] as num?)?.toInt() ?? 1;
      final state = BoostState.fromJson(decoded);

      if (version >= 2) return (state: state, migrated: null);

      return (
        state: state,
        migrated: MachineState.fromJson(decoded),
      );
    } on Object catch (error) {
      onWarning?.call('Ignoring unreadable ${file.path}: $error');
      return null;
    }
  }
```

`BoostState.fromJson` must force `schemaVersion` to `currentSchemaVersion` so a
read-then-write upgrades the file.

- [ ] **Step 5: Update the call sites**

Run: `grep -rn 'BoostStateStore\|\.lastRun\|\.dependencies\|\.fragments' lib/ test/ | grep -v machine_state`

For each hit in `install_command.dart`, `update_command.dart` and
`dependency_drift.dart`: read choices from `BoostStateStore`, read observations
from `MachineStateStore`, and when `read()` returns a non-null `migrated`, write
it to `MachineStateStore` before using it. Drift comparisons now source their
baseline from `MachineState`.

- [ ] **Step 6: Run the full suite**

Run: `dart test`
Expected: PASS. Existing `state_test.dart` assertions about `dependencies` on
`dart_boost.json` must move to `MachineState`; update them rather than deleting
them.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos && dart test
git add lib/src/state/ lib/src/install/dependency_drift.dart lib/src/cli/commands/ test/
git commit -m "Split dart_boost.json into committed choices and per-machine state"
```

---

### Task 6: The MCP server and the `record_rule` tool

**Files:**
- Modify: `pubspec.yaml` (add `dart_mcp`)
- Create: `lib/src/mcp/rules_server.dart`, `bin/mcp.dart`
- Test: `test/rules/rules_server_test.dart`

**Interfaces:**
- Consumes: `RuleRepository` (Task 3).
- Produces: `class DartBoostMcpServer extends MCPServer with ToolsSupport { DartBoostMcpServer(StreamChannel<String> channel, {required RuleRepository repository, required bool rulesEnabled}); }`
  registering a tool named `record_rule` with required string parameters `glob`, `title`, `note`.

- [ ] **Step 1: Add the dependency**

```bash
dart pub add dart_mcp
```

Then edit `pubspec.yaml` so the constraint carries a comment in the house style,
e.g. `dart_mcp: ^0.5.2 # labs.dart.dev; the only file that touches it is lib/src/mcp/rules_server.dart`.

Run: `dart pub get` and confirm the SDK floor did not move.

- [ ] **Step 2: Read the package's server API before writing against it**

Run: `cat $(dart pub cache list --format=json > /dev/null 2>&1; find ~/.pub-cache/hosted -maxdepth 2 -type d -name 'dart_mcp-*' | head -1)/example/*.dart 2>/dev/null | head -60`

`dart_mcp` is 0.5.x and explicitly experimental. Take the exact `MCPServer`
constructor, `registerTool` signature and result types from the installed
version rather than from this plan, and adjust the code below to match.

- [ ] **Step 3: Write the failing test**

```dart
// test/rules/rules_server_test.dart
@TestOn('vm')
library;

import 'package:dart_boost/src/mcp/rules_server.dart';
import 'package:dart_boost/src/rules/rule_repository.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  late RuleRepository repo;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/app').createSync(recursive: true);
    repo = RuleRepository(fileSystem: fs, projectRoot: fs.directory('/app'));
  });

  test('records a rule and reports where it landed', () async {
    final result = await recordRule(
      repository: repo,
      glob: 'lib/models/**',
      title: 'Money is integer cents',
      note: 'Use `int` cents.',
    );

    expect(result.isError, isFalse);
    expect(result.message, contains('.ai/rules/models.md'));
    expect(fs.file('/app/.ai/rules/models.md').existsSync(), isTrue);
    expect(fs.file('/app/.ai/rules/index.md').existsSync(), isTrue);
  });

  test('names every missing parameter in one error', () async {
    final result = await recordRule(
      repository: repo,
      glob: '  ',
      title: '',
      note: 'something',
    );

    expect(result.isError, isTrue);
    expect(result.message, contains('glob'));
    expect(result.message, contains('title'));
    expect(result.message, isNot(contains('note')));
  });

  test('rejects a glob outside the project root without throwing', () async {
    final result = await recordRule(
      repository: repo,
      glob: '../elsewhere/**',
      title: 'Nope',
      note: 'Nope.',
    );

    expect(result.isError, isTrue);
    expect(result.message, contains('outside'));
    expect(fs.directory('/app/.ai/rules').existsSync(), isFalse);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `dart test test/rules/rules_server_test.dart`
Expected: FAIL -- `rules_server.dart` does not exist.

- [ ] **Step 5: Write the implementation**

Keep the validation in a plain function so it is testable without an MCP
transport; the server is the adapter.

```dart
// lib/src/mcp/rules_server.dart
import '../rules/rule_repository.dart';

/// The description is prompt engineering, not documentation: it is what the
/// agent reads when deciding whether this is the moment to record something.
const recordRuleDescription =
    'Record a durable project rule so the next agent or teammate inherits it '
    'instead of working it out again. Use it for a settled decision, a '
    'non-obvious trap, or a standing constraint that must always be followed. '
    'Pass a glob for the files it applies to (for example `lib/models/**`) and '
    'dart_boost files it into a shared, committed markdown note grouped by '
    'area. Keep it to a few lines; only record what you would want to read in '
    'three months. Do not record secrets, transient state, or anything already '
    'obvious from the code.';

class RecordRuleResult {
  const RecordRuleResult({required this.isError, required this.message});

  final bool isError;
  final String message;
}

/// Validates and records. Never throws: an MCP tool that crashes its server is
/// worse than one that returns an error.
Future<RecordRuleResult> recordRule({
  required RuleRepository repository,
  required String glob,
  required String title,
  required String note,
}) async {
  final missing = <String>[
    if (glob.trim().isEmpty) 'glob',
    if (title.trim().isEmpty) 'title',
    if (note.trim().isEmpty) 'note',
  ];

  if (missing.isNotEmpty) {
    return RecordRuleResult(
      isError: true,
      message: 'Missing required ${missing.length == 1 ? 'parameter' : 'parameters'}: '
          '${missing.join(', ')}.',
    );
  }

  try {
    final result = repository.write(glob: glob, title: title, note: note);
    return RecordRuleResult(
      isError: false,
      message: 'Recorded in ${result.path}. '
          '${result.created ? 'Created' : 'Appended to'} that file and '
          'regenerated the index.',
    );
  } on ArgumentError {
    return const RecordRuleResult(
      isError: true,
      message: 'That glob resolves outside the project root. Rules describe '
          'this project, so use a project-relative glob such as `lib/models/**`.',
    );
  } on Object catch (error) {
    return RecordRuleResult(isError: true, message: 'Could not record the rule: $error');
  }
}
```

Then add the `MCPServer` subclass in the same file, wiring a `record_rule` tool
whose handler calls `recordRule` and maps `RecordRuleResult` onto the version's
tool-result type. Register the tool only when `rulesEnabled` is true.

- [ ] **Step 6: Write `bin/mcp.dart`**

```dart
// bin/mcp.dart
import 'dart:io';

import 'package:dart_boost/src/mcp/rules_server.dart';
import 'package:dart_boost/src/rules/rule_repository.dart';
import 'package:file/local.dart';

/// `dart run dart_boost:mcp` -- stdio transport, project root is the cwd,
/// which is what every MCP client sets when it launches a server.
Future<void> main(List<String> args) async {
  const fileSystem = LocalFileSystem();
  final repository = RuleRepository(
    fileSystem: fileSystem,
    projectRoot: fileSystem.currentDirectory,
  );

  await serveRules(
    repository: repository,
    stdin: stdin,
    stdout: stdout,
  );
}
```

Add `serveRules` to `rules_server.dart` wrapping stdin/stdout in the
`StreamChannel<String>` the installed `dart_mcp` expects.

- [ ] **Step 7: Run test to verify it passes**

Run: `dart test test/rules/rules_server_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 8: Smoke-test the real transport**

```bash
mkdir -p /tmp/mcp-smoke && cd /tmp/mcp-smoke
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}\n' \
  | dart run --directory=/Users/taner/codex/booster/dart_boost dart_boost:mcp | head -3
```

Expected: a JSON-RPC result naming the server. If the invocation form differs on
the installed `dart_mcp`, fix it here rather than discovering it at install time.

- [ ] **Step 9: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos && dart test
git add pubspec.yaml pubspec.lock lib/src/mcp/ bin/mcp.dart test/rules/rules_server_test.dart
git commit -m "Add an MCP server exposing record_rule"
```

---

### Task 7: Wire the server into install

**Files:**
- Modify: `lib/src/writers/mcp_writer.dart` (`write` takes `List<McpServerSpec>`)
- Modify: `lib/src/cli/commands/install_command.dart` (build both specs; add the dev dependency; honour `rules.enabled`, `--yes` and CI)
- Create: `lib/src/install/rules_wiring.dart`
- Test: `test/rules/rules_install_test.dart`, plus updates to `test/install_integration_test.dart`

**Interfaces:**
- Consumes: `RulesSettings` (Task 5), `McpServerSpec`/`McpWriter` (existing), `ProcessRunner` (existing).
- Produces:
  `enum RulesWiringOutcome { disabled, alreadyPresent, added, declined, skippedUnattended, failed }` and
  `RulesWiringOutcome ensureDevDependency({required Project project, required ProcessRunner processes, required bool interactive, required bool dryRun, required bool Function(String) confirm, required void Function(String) log})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/rules_install_test.dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  Future<void> project({String pubspec = 'name: app\nenvironment:\n  sdk: ^3.7.0\n'}) =>
      d.dir('app', <d.Descriptor>[d.file('pubspec.yaml', pubspec)]).create();

  test('writes both MCP servers when dart_boost is already a dev dependency', () async {
    await project(
      pubspec: 'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n',
    );

    final result = await runCli(<String>[
      'install', '-C', d.path('app'), '--agents=claude_code', '--yes',
    ]);

    expect(result.exitCode, 0);
    final config = await readJson(d.path('app/.mcp.json'));
    expect((config['mcpServers']! as Map).keys, containsAll(<String>['dart', 'dart_boost']));
    expect(
      ((config['mcpServers']! as Map)['dart_boost']! as Map)['args'],
      <String>['run', 'dart_boost:mcp'],
    );
  });

  test('skips rules wiring unattended rather than editing pubspec.yaml', () async {
    await project();
    final before = await readFile(d.path('app/pubspec.yaml'));

    final result = await runCli(<String>[
      'install', '-C', d.path('app'), '--agents=claude_code', '--yes',
    ]);

    expect(result.exitCode, 0);
    expect(await readFile(d.path('app/pubspec.yaml')), before);

    final config = await readJson(d.path('app/.mcp.json'));
    expect((config['mcpServers']! as Map).keys, <String>['dart']);
    expect(result.output, contains('rules'));
    expect(result.output, contains('dev dependency'));
  });

  test('writes no rules server when rules are disabled', () async {
    await project(
      pubspec: 'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n',
    );
    await d.dir('app', <d.Descriptor>[
      d.file('dart_boost.json',
          '{"version":2,"agents":["claude_code"],'
          '"features":{"guidelines":true,"mcp":true},'
          '"rules":{"enabled":false}}'),
    ]).create();

    await runCli(<String>['update', '-C', d.path('app'), '--yes']);

    final config = await readJson(d.path('app/.mcp.json'));
    expect((config['mcpServers']! as Map).keys, <String>['dart']);
  });

  test('re-running reports already up to date', () async {
    await project(
      pubspec: 'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n',
    );
    await runCli(<String>['install', '-C', d.path('app'), '--agents=claude_code', '--yes']);
    final second = await runCli(<String>['install', '-C', d.path('app'), '--agents=claude_code', '--yes']);

    expect(second.output, contains('already up to date'));
  });
}
```

Add `readJson` and `readFile` helpers to `test/support/cli_harness.dart` if they
are not already there.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/rules_install_test.dart`
Expected: FAIL -- `.mcp.json` contains only the `dart` server.

- [ ] **Step 3: Let `McpWriter` write several servers**

Change the signature to `required List<McpServerSpec> specs` and build one
splice map from all of them:

```dart
    final entries = <String, Object?>{
      for (final spec in specs) spec.key: agent.mcpEntry(spec),
    };
```

for JSON/JSONC, and the `Map<String, Map<String, Object?>>` equivalent for TOML.
One report per agent, unchanged. Update every call site found by
`grep -rn 'McpWriter(' lib/ test/`.

- [ ] **Step 4: Add the dev-dependency step**

```dart
// lib/src/install/rules_wiring.dart
import '../project/project.dart';
import '../util/process_runner.dart';

enum RulesWiringOutcome {
  disabled('rules are disabled'),
  alreadyPresent('dart_boost is already a dev dependency'),
  added('added dart_boost as a dev dependency'),
  declined('declined'),
  skippedUnattended('skipped: no one to confirm the pubspec change'),
  failed('could not add the dev dependency');

  const RulesWiringOutcome(this.label);

  final String label;
}

/// `dart run dart_boost:mcp` only resolves when dart_boost is a dependency of
/// the target project, so enabling rules means adding one.
///
/// Editing `pubspec.yaml` on a machine that never asked is the same class of
/// action as downloading a package unasked, which `--skills` already refuses.
/// So unattended runs skip the wiring and say so; the guidelines and the SDK
/// MCP entry are still written.
RulesWiringOutcome ensureDevDependency({
  required Project project,
  required ProcessRunner processes,
  required bool interactive,
  required bool dryRun,
  required bool Function(String) confirm,
  required void Function(String) log,
}) {
  if (project.hasDependency('dart_boost')) {
    return RulesWiringOutcome.alreadyPresent;
  }

  if (!interactive) {
    log(
      'Project rules need dart_boost as a dev dependency, and adding one '
      'unattended is not something to do on a machine that did not ask. '
      'Run `dart pub add dev:dart_boost` and re-run, or pass --no-rules.',
    );
    return RulesWiringOutcome.skippedUnattended;
  }

  if (!confirm('Add dart_boost as a dev dependency so agents can record project rules?')) {
    return RulesWiringOutcome.declined;
  }

  if (dryRun) return RulesWiringOutcome.added;

  final result = processes.run('dart', <String>['pub', 'add', 'dev:dart_boost']);
  if (!result.succeeded) {
    log('`dart pub add dev:dart_boost` failed; rules were not wired. ${result.stderr}');
    return RulesWiringOutcome.failed;
  }

  return RulesWiringOutcome.added;
}
```

Add `bool hasDependency(String name)` to `Project` if it does not exist, backed
by the already-resolved direct dependency set.

- [ ] **Step 5: Call it from install**

In `install_command.dart`, before writing MCP config: if `state.rules.enabled`
and `features.mcp`, call `ensureDevDependency`. Include the `dart_boost` spec
only when the outcome is `alreadyPresent` or `added`:

```dart
    final specs = <McpServerSpec>[
      dartSpec,
      if (rulesWired)
        McpServerSpec(
          key: 'dart_boost',
          command: dartSpec.command,
          args: const <String>['run', 'dart_boost:mcp'],
        ),
    ];
```

Reusing `dartSpec.command` means the FVM-pinned absolute path is inherited with
no new resolution logic. Add `--[no-]rules` to install and update, defaulting to
the saved choice, and report the outcome label in the existing summary block.

- [ ] **Step 6: Run tests**

Run: `dart test test/rules/rules_install_test.dart && dart test`
Expected: PASS. `install_integration_test.dart` assertions that pin the exact
`mcpServers` key set need updating to allow the second server.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos && dart test
git add lib/src/writers/mcp_writer.dart lib/src/install/rules_wiring.dart lib/src/cli/commands/ lib/src/project/project.dart test/
git commit -m "Wire the rules MCP server into install behind a confirmed dev dependency"
```

---

### Task 8: The guidelines stanza

**Files:**
- Create: `guidelines/rules.md`
- Modify: `lib/src/guidelines/composer.dart:103` area (add to the always-composed core block)
- Test: `test/rules/rules_fragment_test.dart`

**Interfaces:**
- Consumes: `assets.fragment(String key)` (existing).
- Produces: fragment key `rules`, composed for every project.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/rules_fragment_test.dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('every project gets the rules stanza, with or without rules on disk', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
    ]).create();

    final result = await runCli(<String>['compose', '-C', d.path('app')]);

    expect(result.output, contains('=== rules rules ==='));
    expect(result.output, contains('.ai/rules/index.md'));
    expect(result.output, contains('.ai/infer-conventions.md'));
  });

  test('the stanza carries no unrendered directives', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
    ]).create();

    final result = await runCli(<String>['compose', '-C', d.path('app')]);

    expect(result.output, isNot(contains('boost:if')));
    expect(result.output, isNot(contains('{{')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/rules_fragment_test.dart`
Expected: FAIL -- output has no `=== rules rules ===` section.

- [ ] **Step 3: Write the fragment**

```markdown
<!-- guidelines/rules.md -->
# Project rules

This project records its own decisions as rules, separately from the general
guidance above. Rules describe *this* codebase, and they outrank anything here
that contradicts them.

**Before planning or editing any file**, check `.ai/rules/index.md` if it
exists. Find the row whose globs match the file's path and read that rule file.
Read only the rows that match -- the index exists so that rules for parts of
the codebase you are not touching stay out of the way.

When you learn something durable about this project -- a settled decision, a
non-obvious trap, a standing constraint -- record it with the `record_rule`
tool rather than writing a rule file by hand. The index is regenerated on every
recorded rule, and a hand-written file stays invisible to other agents until it
is. Do not record secrets, transient state, or anything already obvious from
the code.

When asked to infer this project's conventions, read `.ai/infer-conventions.md`
and follow it.
```

The stanza is unconditional: a `hasProjectRules` flag would leave the first
recorded rule unannounced until the next `install` or `update`.

- [ ] **Step 4: Compose it**

In `lib/src/guidelines/composer.dart`, in the `// --- core (always) ---` block:

```dart
    add('rules', assets.fragment('rules'));
```

Place it after `add('foundation', ...)` and before `add('dart', ...)`.

- [ ] **Step 5: Run tests**

Run: `dart test test/rules/rules_fragment_test.dart && dart test`
Expected: PASS. `bundled_guidelines_test.dart` and `composer_test.dart` fragment
counts and key lists need updating for the new always-on key.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos && dart test
git add guidelines/rules.md lib/src/guidelines/composer.dart test/
git commit -m "Compose a project-rules stanza into every project's guidelines"
```

---

### Task 9: Ship the infer-conventions procedure

**Files:**
- Create: `assets/infer-conventions.md`
- Modify: `lib/src/assets/bundled_assets.dart` (expose the `assets/` tree), `tool/verify_assets.dart` (verify both trees), `lib/src/writers/guidelines_writer.dart` or a new writer call in `install_command.dart`
- Test: `test/rules/infer_conventions_test.dart`, `test/verify_assets_test.dart` (extend)

**Interfaces:**
- Consumes: `BundledAssets` (existing).
- Produces: `File? BundledAssets.asset(String relativePath)` and a written
  `.ai/infer-conventions.md` in the target project.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/infer_conventions_test.dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('install writes the procedure into the project', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n'),
    ]).create();

    await runCli(<String>['install', '-C', d.path('app'), '--agents=claude_code', '--yes']);

    final content = await readFile(d.path('app/.ai/infer-conventions.md'));
    expect(content, contains('record_rule'));
    expect(content, contains('analysis_options.yaml'));
    expect(content, contains('state management'));
  });

  test('the procedure is not written when rules are disabled', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      d.file('dart_boost.json',
          '{"version":2,"agents":["claude_code"],'
          '"features":{"guidelines":true,"mcp":true},'
          '"rules":{"enabled":false}}'),
    ]).create();

    await runCli(<String>['update', '-C', d.path('app'), '--yes']);

    expect(await exists(d.path('app/.ai/infer-conventions.md')), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/infer_conventions_test.dart`
Expected: FAIL -- the file is not written.

- [ ] **Step 3: Write the procedure**

Create `assets/infer-conventions.md`. It is prose the agent follows, so write it
as instructions, and include every rule below verbatim in substance:

```markdown
# Infer this project's conventions

Bootstrap `.ai/rules` from the code that already exists here. Recording rules
one at a time works going forward; this is the pass that catches what the
project already decided.

## How to run the sweep

Work through these dimensions one at a time. For each, read a representative
sample of the files that dimension covers -- not every file -- and write down
the pattern you actually see.

- **State management** -- which solution, how providers/blocs/notifiers are
  named, where they live, how they are scoped and disposed.
- **Widget composition** -- StatelessWidget vs StatefulWidget vs hooks, when a
  widget gets extracted, const usage, how build methods are kept small.
- **Navigation and routing** -- declarative vs imperative, where routes are
  declared, how arguments and deep links are typed.
- **Error handling** -- Result types vs exceptions, where errors are caught,
  what reaches the user, how failures are logged.
- **Async and streams** -- Future vs Stream conventions, cancellation,
  `mounted` checks after await, timeout policy.
- **Testing** -- unit vs widget vs integration split, fake vs mock, fixture and
  helper layout, what is asserted and what is not.
- **Code generation** -- which generators, whether generated files are
  committed, the exact build command.
- **Project layout** -- feature-first vs layer-first, package boundaries in a
  monorepo, what belongs in `lib/src`.

Then make one open-ended pass for base classes, shared mixins, extension
conventions and module boundaries that the list above does not name.

## What to record, and what not to

- **Document what the code does, not what it should do.** This is a description
  of the project, not a wish list.
- **Record only well-supported, non-default conventions.** If you cannot point
  to several files doing it, it is not a convention yet.
- **Skip anything the linter already enforces.** Read `analysis_options.yaml`
  first and never restate a rule it already covers. `dart format` settles
  formatting; do not write rules about it.
- **Report mixed patterns instead of recording them.** If half the codebase
  does it one way and half the other, say so and let a human decide. A rule
  that codifies a coin flip is worse than no rule.

## Before writing anything

Present every convention you found, each with the evidence that supports it --
the files you saw it in and the count. Wait for approval. The person reading
this knows which patterns are deliberate and which are accidents.

Once a convention is approved, record it with the `record_rule` tool: a `glob`
for the files it applies to, a short specific `title`, and a `note` of a few
lines. Do not write rule files by hand -- the index is regenerated by the tool,
and a hand-written file stays invisible until it is.
```

- [ ] **Step 4: Expose and write the asset**

In `bundled_assets.dart`, add alongside `guidelines`:

```dart
  /// `<root>/assets` -- files copied verbatim into the target project.
  ///
  /// Not dot-prefixed, for the same reason `guidelines/` is not: publishing
  /// strips dot-prefixed paths and the release would silently lack them.
  final Directory assets;

  File? asset(String relativePath) {
    final file = fileSystem.file(p.join(assets.path, p.joinAll(relativePath.split('/'))));
    return file.existsSync() ? file : null;
  }
```

Resolve `assets` next to `guidelines` in the same locator, and in
`install_command.dart` write `assets/infer-conventions.md` to
`.ai/infer-conventions.md` through `AtomicWriter`, only when `rules.enabled`,
reporting it in the existing file-summary block.

- [ ] **Step 5: Extend the packaging guard**

In `tool/verify_assets.dart`, verify both trees. Replace the single `guidelines`
directory with a loop over `['guidelines', 'assets']`, keeping the existing
manifest parsing and failure messages.

- [ ] **Step 6: Run tests**

Run: `dart test test/rules/infer_conventions_test.dart && dart test && dart run tool/verify_assets.dart`
Expected: PASS, and the asset guard confirms both trees survive packaging.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format . && dart analyze --fatal-infos && dart test
git add assets/ lib/src/assets/bundled_assets.dart lib/src/cli/commands/install_command.dart tool/verify_assets.dart test/
git commit -m "Ship the infer-conventions procedure and guard the assets tree"
```

---

### Task 10: doctor, docs, and the release pass

**Files:**
- Modify: `lib/src/cli/commands/doctor_command.dart`, `README.md`, `CHANGELOG.md`, `VERIFICATION.md`, `pubspec.yaml` (version)
- Test: `test/rules/rules_doctor_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: no new public API.

- [ ] **Step 1: Write the failing test**

```dart
// test/rules/rules_doctor_test.dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('doctor reports the rules server and the rule count', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n'),
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[
          d.file('models.md', '---\npaths:\n  - lib/models/**\n---\n\n# Models\n\n## A\n\na\n'),
        ]),
      ]),
    ]).create();

    final result = await runCli(<String>['doctor', '-C', d.path('app')]);

    expect(result.output, contains('Rules'));
    expect(result.output, contains('1 rule file'));
    expect(result.output, contains('dart run dart_boost:mcp'));
  });

  test('doctor says why rules are not wired when dart_boost is absent', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
    ]).create();

    final result = await runCli(<String>['doctor', '-C', d.path('app')]);

    expect(result.output, contains('not a dev dependency'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rules/rules_doctor_test.dart`
Expected: FAIL -- no `Rules` section in the doctor output.

- [ ] **Step 3: Add the doctor section**

Follow the existing section formatting in `doctor_command.dart` exactly. Report:
the rules directory and whether it exists, the number of parsed rule files and
any that failed to parse, whether `dart_boost` is a dev dependency, the server
command, and the probe result -- reusing `McpCommandResolver.probe` the way the
`dart mcp-server` line already does.

- [ ] **Step 4: Run tests**

Run: `dart test test/rules/rules_doctor_test.dart && dart test`
Expected: PASS.

- [ ] **Step 5: Update the docs**

- `README.md`: add a **Project rules** section covering `.ai/rules/`, the index,
  `record_rule`, `infer-conventions` and `rules index`. Remove "path-scoped
  rules" from *Status*. Rewrite the **State** section for the two files. Qualify
  "Nothing to add to your `pubspec.yaml`" -- still true with `--no-rules`.
  Add the second server to the MCP section.
- `CHANGELOG.md`: a `0.2.0` entry covering project rules, the MCP server, the
  state split and the migration.
- `VERIFICATION.md`: correct the stale test count (it says 293; the suite is
  409 before this work) and note that the Phase 1-3 pass predates rules.
- `pubspec.yaml`: bump `version` to `0.2.0`.

- [ ] **Step 6: Full verification**

```bash
dart format --set-exit-if-changed . \
  && dart analyze --fatal-infos \
  && dart test \
  && dart run tool/verify_assets.dart
```

Expected: all four clean. Record the resulting test count for `VERIFICATION.md`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Report rules in doctor and document the 0.2.0 release"
```

---

## Manual verification

After Task 10, repeat the end-to-end pass that validated 0.1.0, in a scratch
directory outside the repo:

1. `flutter create demo_app`, add `flutter_riverpod`, `go_router`, `dio`, `git init`, commit.
2. `dart pub add dev:dart_boost --path <repo>` then
   `dart run dart_boost install --agents=claude_code --yes`.
3. Confirm `.mcp.json` holds both servers, `.ai/infer-conventions.md` exists, and
   `CLAUDE.md` carries the rules stanza.
4. Re-run install: every line reports "already up to date" and `git status` is empty.
5. Point Claude Code at the project and ask it to remember something. Confirm
   `.ai/rules/*.md` and `index.md` appear, and that `git status` shows only those.
6. Ask it to edit a file the rule's glob covers; confirm it reads the index.
7. `dart run dart_boost doctor` reports the rules section correctly.
8. Break `.ai/rules/index.md`, run `dart run dart_boost rules index`, confirm repair.
9. In a project *without* dart_boost as a dev dependency, run
   `install --yes` and confirm `pubspec.yaml` is byte-identical afterwards.
