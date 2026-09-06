import 'package:dart_boost/src/writers/guidelines_writer.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late GuidelinesWriter writer;
  late String path;

  setUp(() {
    fs = memoryFs();
    writer = GuidelinesWriter(fs);
    path = p.join(fs.currentDirectory.path, 'app', 'CLAUDE.md');
    fs.directory(p.dirname(path)).createSync(recursive: true);
  });

  String read() => fs.file(path).readAsStringSync();

  test('creates the file with a sentinel block', () {
    final outcome = writer.write(path: path, guidelines: '# Rules\nbe good');

    expect(outcome, GuidelineWriteOutcome.created);
    expect(read(), '''
<dart-boost-guidelines>
# Rules
be good

</dart-boost-guidelines>
''');
  });

  test('appends after existing content, separated by ===', () {
    fs.file(path).writeAsStringSync('# My notes\n\nkeep these\n');

    writer.write(path: path, guidelines: 'generated');

    expect(read(), contains('# My notes'));
    expect(read(), contains('keep these\n\n===\n\n<dart-boost-guidelines>'));
  });

  test('replaces in place, so content after the block keeps its position', () {
    // Boost passes `limit: 1` here deliberately. Appending instead would shunt
    // the user's trailing sections below ours on every single run.
    fs.file(path).writeAsStringSync('''
before

<dart-boost-guidelines>
old
</dart-boost-guidelines>

after
''');

    final outcome = writer.write(path: path, guidelines: 'new');

    expect(outcome, GuidelineWriteOutcome.replaced);
    final result = read();
    expect(result.indexOf('before'), lessThan(result.indexOf('new')));
    expect(result.indexOf('new'), lessThan(result.indexOf('after')));
    expect(result, isNot(contains('old')));
  });

  test('is idempotent', () {
    writer.write(path: path, guidelines: 'generated');
    final first = read();

    final outcome = writer.write(path: path, guidelines: 'generated');

    expect(outcome, GuidelineWriteOutcome.unchanged);
    expect(read(), first);
  });

  test('collapses blank-line runs and guarantees a trailing newline', () {
    fs.file(path).writeAsStringSync('a\n\n\n\n\nb');

    writer.write(path: path, guidelines: 'x');

    expect(read(), startsWith('a\n\nb\n'));
    expect(read(), endsWith('\n'));
  });

  test('adds frontmatter only when asked and only when absent', () {
    writer.write(path: path, guidelines: 'x', frontmatter: true);
    expect(read(), startsWith('---\nalwaysApply: true\n---\n'));

    final withExisting = p.join(fs.currentDirectory.path, 'app', 'OTHER.md');
    fs.file(withExisting).writeAsStringSync('---\ntitle: mine\n---\nbody\n');
    writer.write(path: withExisting, guidelines: 'x', frontmatter: true);
    expect(
      RegExp(
        'alwaysApply',
      ).allMatches(fs.file(withExisting).readAsStringSync()).length,
      0,
    );
  });

  test('empty guidelines write nothing', () {
    expect(
      writer.write(path: path, guidelines: '   \n'),
      GuidelineWriteOutcome.empty,
    );
    expect(fs.file(path).existsSync(), isFalse);
  });

  test('a dry run reports the outcome without touching the file', () {
    fs.file(path).writeAsStringSync('original\n');

    final outcome = GuidelinesWriter(
      fs,
      dryRun: true,
    ).write(path: path, guidelines: 'x');

    expect(outcome, GuidelineWriteOutcome.created);
    expect(read(), 'original\n');
  });

  test('a dry run does not conjure the file into existence', () {
    // Opening with `FileMode.append` creates the file, so the dry-run path
    // must not open it at all.
    final outcome = GuidelinesWriter(
      fs,
      dryRun: true,
    ).write(path: path, guidelines: 'x');

    expect(outcome, GuidelineWriteOutcome.created);
    expect(fs.file(path).existsSync(), isFalse);
  });
}
