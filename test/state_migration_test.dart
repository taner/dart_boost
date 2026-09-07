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
    expect(result.migrated!.dependencies, <String, String>{
      'go_router': '18.2.0',
    });
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
    store.write(
      const MachineState(
        dependencies: <String, String>{'dio': '5.11.1'},
        fragments: <String>['dio/core'],
        lastRun: LastRun(flutter: '3.47.2'),
      ),
    );

    expect(store.file.path, '/app/.dart_tool/dart_boost/state.json');
    expect(store.read()!.dependencies, <String, String>{'dio': '5.11.1'});
  });

  test('a v1 file with a corrupt observation warns during migration, '
      'not just silently', () {
    // `dependencies` present but wrong-typed: not an absent key (which
    // would quietly mean "predates this field") and not a valid one either.
    // The migration path shares `MachineState.fromJson` with
    // `MachineStateStore`, so it must forward `onWarning` the same way.
    writeV1(<String, Object?>{
      'version': 1,
      'agents': <String>['claude_code'],
      'features': <String, Object?>{'guidelines': true, 'mcp': true},
      'dependencies': 'not a map',
    });
    final warnings = <String>[];

    final result =
        BoostStateStore(
          fs,
          fs.directory('/app'),
        ).read(onWarning: warnings.add)!;

    expect(result.migrated!.dependencies, isNull);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('dependencies'));
  });
}
