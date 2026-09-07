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
