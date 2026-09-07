import 'dart:convert';

import 'package:dart_boost/src/state/boost_state.dart';
import 'package:dart_boost/src/state/machine_state.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late BoostStateStore store;
  late MachineStateStore machineStore;

  setUp(() {
    fs = memoryFs();
    final root = fs.directory(p.join(fs.currentDirectory.path, 'app'))
      ..createSync(recursive: true);
    store = BoostStateStore(fs, root);
    machineStore = MachineStateStore(fs, root);
  });

  test('round-trips', () {
    final state = BoostState(
      agents: ['claude_code', 'copilot', 'codex'],
      thirdPartyPackages: ['serverpod'],
      delegateSkills: true,
    );

    store.write(state);
    final read = store.read()!.state;

    expect(read.agents, state.agents);
    expect(read.thirdPartyPackages, ['serverpod']);
    expect(read.delegateSkills, isTrue);
    expect(read.guidelines, isTrue);
    expect(read.mcp, isTrue);
    expect(read.trusts('serverpod'), isTrue);
    expect(read.trusts('anything_else'), isFalse);
  });

  test('writes the documented shape', () {
    store.write(BoostState(agents: ['claude_code']));

    final decoded =
        jsonDecode(store.file.readAsStringSync()) as Map<String, Object?>;
    expect(decoded['version'], 2);
    expect(decoded['agents'], ['claude_code']);
    expect(decoded['features'], {'guidelines': true, 'mcp': true});
    expect(decoded['thirdPartyPackages'], isEmpty);
    expect(decoded, isNot(contains('lastRun')));
    expect(decoded, isNot(contains('dependencies')));
    expect(decoded, isNot(contains('fragments')));
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
    store.file.writeAsStringSync('{"version": 2, "agents": ["cursor"]}');
    final read = store.read()!.state;

    expect(read.agents, ['cursor']);
    expect(read.guidelines, isTrue);
    expect(read.mcp, isTrue);
    expect(read.delegateSkills, isFalse);
    expect(read.rules.enabled, isTrue);
  });

  group('MachineState', () {
    test('round-trips through its own store, separate from choices', () {
      machineStore.write(
        const MachineState(
          dependencies: {'go_router': '18.2.0'},
          fragments: ['go_router/v18'],
          lastRun: LastRun(
            flutter: '3.47.2',
            dart: '3.13.2',
            boostVersion: '0.1.0',
          ),
        ),
      );
      final read = machineStore.read()!;

      expect(read.dependencies, {'go_router': '18.2.0'});
      expect(read.fragments, ['go_router/v18']);
      expect(read.lastRun!.flutter, '3.47.2');
      expect(machineStore.file.path, contains('.dart_tool'));
      // Writing machine state must never touch the committed choices file.
      expect(store.exists, isFalse);
    });

    test('an absent machine state file is null, not an error', () {
      expect(machineStore.read(), isNull);
      expect(machineStore.exists, isFalse);
    });

    test('a corrupt machine state file warns and is ignored', () {
      machineStore.file.parent.createSync(recursive: true);
      machineStore.file.writeAsStringSync('{ this is not json');
      final warnings = <String>[];

      expect(machineStore.read(onWarning: warnings.add), isNull);
      expect(warnings, hasLength(1));
    });

    test('missing dependencies/fragments stay null, not empty', () {
      machineStore.write(const MachineState());
      final read = machineStore.read()!;

      expect(read.dependencies, isNull);
      expect(read.fragments, isNull);
      expect(read.lastRun, isNull);
    });

    // A genuinely empty map/list is a real baseline ("no dependencies"), not
    // the same as the key being absent. A wrong-typed *value* is neither of
    // those -- it is corruption -- and must not be silently coerced into that
    // same empty baseline, or the next `update` would announce every current
    // dependency as newly added with no sign anything was wrong.
    group('a present key with the wrong type', () {
      test('dependencies: not a map becomes null, with a warning', () {
        machineStore.file.parent.createSync(recursive: true);
        machineStore.file.writeAsStringSync(
          jsonEncode({'version': 2, 'dependencies': 'oops'}),
        );
        final warnings = <String>[];

        final read = machineStore.read(onWarning: warnings.add)!;

        expect(read.dependencies, isNull);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('dependencies'));
      });

      test('fragments: not a list becomes null, with a warning', () {
        machineStore.file.parent.createSync(recursive: true);
        machineStore.file.writeAsStringSync(
          jsonEncode({'version': 2, 'fragments': 42}),
        );
        final warnings = <String>[];

        final read = machineStore.read(onWarning: warnings.add)!;

        expect(read.fragments, isNull);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('fragments'));
      });

      test('lastRun: not a map becomes null, with a warning', () {
        machineStore.file.parent.createSync(recursive: true);
        machineStore.file.writeAsStringSync(
          jsonEncode({
            'version': 2,
            'lastRun': ['not', 'a', 'map'],
          }),
        );
        final warnings = <String>[];

        final read = machineStore.read(onWarning: warnings.add)!;

        expect(read.lastRun, isNull);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('lastRun'));
      });

      test('nothing throws for any wrong-typed field', () {
        machineStore.file.parent.createSync(recursive: true);
        machineStore.file.writeAsStringSync(
          jsonEncode({
            'version': 2,
            'dependencies': 'oops',
            'fragments': 42,
            'lastRun': true,
          }),
        );

        expect(() => machineStore.read(onWarning: (_) {}), returnsNormally);
      });
    });

    test('a genuinely empty map/list still round-trips as empty, not null', () {
      machineStore.file.parent.createSync(recursive: true);
      machineStore.file.writeAsStringSync(
        jsonEncode({
          'version': 2,
          'dependencies': <String, Object?>{},
          'fragments': <Object?>[],
        }),
      );
      final warnings = <String>[];

      final read = machineStore.read(onWarning: warnings.add)!;

      expect(read.dependencies, isNotNull);
      expect(read.dependencies, isEmpty);
      expect(read.fragments, isNotNull);
      expect(read.fragments, isEmpty);
      expect(warnings, isEmpty);
    });
  });
}
