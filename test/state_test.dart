import 'dart:convert';

import 'package:dart_boost/src/state/boost_state.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late BoostStateStore store;

  setUp(() {
    fs = memoryFs();
    final root = fs.directory(p.join(fs.currentDirectory.path, 'app'))
      ..createSync(recursive: true);
    store = BoostStateStore(fs, root);
  });

  test('round-trips', () {
    final state = BoostState(
      agents: ['claude_code', 'copilot', 'codex'],
      thirdPartyPackages: ['serverpod'],
      delegateSkills: true,
      lastRun: const LastRun(
        flutter: '3.47.2',
        dart: '3.13.2',
        boostVersion: '0.1.0',
      ),
    );

    store.write(state);
    final read = store.read()!;

    expect(read.agents, state.agents);
    expect(read.thirdPartyPackages, ['serverpod']);
    expect(read.delegateSkills, isTrue);
    expect(read.guidelines, isTrue);
    expect(read.mcp, isTrue);
    expect(read.lastRun!.flutter, '3.47.2');
    expect(read.trusts('serverpod'), isTrue);
    expect(read.trusts('anything_else'), isFalse);
  });

  test('writes the documented shape', () {
    store.write(
      BoostState(
        agents: ['claude_code'],
        lastRun: const LastRun(flutter: '3.47.2'),
      ),
    );

    final decoded =
        jsonDecode(store.file.readAsStringSync()) as Map<String, Object?>;
    expect(decoded['version'], 1);
    expect(decoded['agents'], ['claude_code']);
    expect(decoded['features'], {'guidelines': true, 'mcp': true});
    expect(decoded['thirdPartyPackages'], isEmpty);
    expect(decoded['lastRun'], {'flutter': '3.47.2'});
  });

  test('an absent state file is null, not an error', () {
    expect(store.read(), isNull);
    expect(store.exists, isFalse);
  });

  test(
    'a corrupt state file warns and is ignored, never blocking a re-install',
    () {
      store.file.writeAsStringSync('{ this is not json');
      final warnings = <String>[];

      expect(store.read(onWarning: warnings.add), isNull);
      expect(warnings, hasLength(1));
    },
  );

  test('missing optional fields fall back to safe defaults', () {
    store.file.writeAsStringSync('{"version": 1, "agents": ["cursor"]}');
    final read = store.read()!;

    expect(read.agents, ['cursor']);
    expect(read.guidelines, isTrue);
    expect(read.mcp, isTrue);
    expect(read.delegateSkills, isFalse);
    expect(read.lastRun, isNull);
  });
}
