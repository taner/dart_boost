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
    final second = repo.write(
      glob: 'lib/models/*.dart',
      title: 'Second',
      note: 'Two.',
    );

    expect(second.path, '/app/.ai/rules/models.md');
    expect(second.created, isFalse);

    final content = read(second.path);
    expect(content, contains('## First'));
    expect(content, contains('## Second'));
    expect(content, contains('  - lib/models/**'));
    expect(content, contains('  - lib/models/*.dart'));
    expect(
      fs.directory('/app/.ai/rules').listSync().whereType<File>().length,
      2,
    ); // rule + index
  });

  test('a different area gets its own file', () {
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    final other = repo.write(glob: 'lib/widgets/**', title: 'B', note: 'b');

    expect(other.path, '/app/.ai/rules/widgets.md');
  });

  test('widens the slug when the short name is taken by another area', () {
    repo.write(glob: 'lib/widgets/**', title: 'A', note: 'a');
    final other = repo.write(
      glob: 'packages/ui/widgets/**',
      title: 'B',
      note: 'b',
    );

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

    final fs2 =
        MemoryFileSystem.test()..directory('/app').createSync(recursive: true);
    final repo2 = RuleRepository(
      fileSystem: fs2,
      projectRoot: fs2.directory('/app'),
    );
    repo2.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo2.write(glob: 'test/**', title: 'B', note: 'b');

    expect(fs2.file('/app/.ai/rules/index.md').readAsStringSync(), first);
  });

  test('a malformed rule file is skipped, warned about, and left on disk', () {
    fs.directory('/app/.ai/rules').createSync(recursive: true);
    fs
        .file('/app/.ai/rules/broken.md')
        .writeAsStringSync('no frontmatter here\n');

    final warnings = <String>[];
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo.writeIndex(onWarning: warnings.add);

    expect(warnings.single, contains('broken.md'));
    expect(
      fs.file('/app/.ai/rules/broken.md').readAsStringSync(),
      'no frontmatter here\n',
    );
    expect(read('/app/.ai/rules/index.md'), isNot(contains('broken.md')));
  });

  test('appending to a CRLF rule file preserves its line endings', () {
    fs.directory('/app/.ai/rules').createSync(recursive: true);
    fs
        .file('/app/.ai/rules/models.md')
        .writeAsStringSync(
          '---\r\npaths:\r\n  - lib/models/**\r\n---\r\n\r\n'
          '# Models\r\n\r\n## First\r\n\r\nOne.\r\n',
        );

    repo.write(glob: 'lib/models/*.dart', title: 'Second', note: 'Two.');

    final content = read('/app/.ai/rules/models.md');
    expect(content, contains('\r\n'));
    expect(content, isNot(contains(RegExp(r'(?<!\r)\n'))));
    expect(content, contains('## Second\r\n\r\nTwo.'));
  });

  test('writing the same rule twice does not duplicate the glob', () {
    repo.write(glob: 'lib/models/**', title: 'A', note: 'a');
    repo.write(glob: 'lib/models/**', title: 'B', note: 'b');

    final content = read('/app/.ai/rules/models.md');
    expect('  - lib/models/**'.allMatches(content).length, 1);
  });
}
