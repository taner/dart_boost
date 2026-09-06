import 'package:dart_boost/src/install/dependency_drift.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  Project projectWith(Map<String, String> lock) {
    final fs = memoryFs();
    final fake =
        FakeProject(fs, '/app')
          ..pubspec(
            flutter: false,
            dependencies: <String, String>{
              for (final name in lock.keys)
                if (!lock[name]!.contains('dev')) name: 'any',
            },
            devDependencies: <String, String>{
              for (final name in lock.keys)
                if (lock[name]!.contains('dev')) name: 'any',
            },
          )
          ..lock(lock);
    return ProjectResolver(
      fileSystem: fs,
      processRunner: FakeProcessRunner(),
    ).resolve(fake.root);
  }

  group('snapshotDependencies', () {
    test('records direct dependencies only, sorted', () {
      final project = projectWith(<String, String>{
        'riverpod': '3.0.1 direct main',
        'build_runner': '2.4.9 direct dev',
        'meta': '1.15.0 transitive',
      });

      expect(snapshotDependencies(project), <String, String>{
        'build_runner': '2.4.9',
        'riverpod': '3.0.1',
      });
    });
  });

  group('diffDependencies', () {
    test('reports nothing when the previous run recorded nothing', () {
      // A `dart_boost.json` written before this field existed. Reporting every
      // dependency as new here would be the loudest possible way to be wrong.
      final drift = diffDependencies(
        projectWith(<String, String>{'riverpod': '3.0.1 direct main'}),
        null,
      );

      expect(drift.recorded, isFalse);
      expect(drift.isEmpty, isTrue);
    });

    test('finds an added dependency', () {
      final drift = diffDependencies(
        projectWith(<String, String>{
          'riverpod': '3.0.1 direct main',
          'go_router': '18.0.1 direct main',
        }),
        <String, String>{'riverpod': '3.0.1'},
      );

      expect(drift.added.map((c) => c.name), <String>['go_router']);
      expect(drift.added.single.describe(), '+ go_router 18.0.1');
      expect(drift.removed, isEmpty);
      expect(drift.isEmpty, isFalse);
    });

    test('finds a removed dependency', () {
      final drift = diffDependencies(
        projectWith(<String, String>{'riverpod': '3.0.1 direct main'}),
        <String, String>{'riverpod': '3.0.1', 'bloc': '9.0.0'},
      );

      expect(drift.removed.single.describe(), '- bloc 9.0.0');
    });

    test('a patch bump is not a re-key, a major bump is', () {
      final patch = diffDependencies(
        projectWith(<String, String>{'riverpod': '3.0.2 direct main'}),
        <String, String>{'riverpod': '3.0.1'},
      );
      // The fragment directory is keyed on the major, so 3.0.1 -> 3.0.2
      // composes byte-identical guidance and is not worth a line of output.
      expect(patch.rekeyed, isEmpty);
      expect(patch.isEmpty, isTrue);

      final major = diffDependencies(
        projectWith(<String, String>{'riverpod': '3.0.1 direct main'}),
        <String, String>{'riverpod': '2.6.1'},
      );
      expect(major.rekeyed.single.describe(), '  riverpod 2.6.1 -> 3.0.1');
    });

    test('a pre-1.0 minor bump re-keys, matching versionKey', () {
      final drift = diffDependencies(
        projectWith(<String, String>{'tiny': '0.4.0 direct main'}),
        <String, String>{'tiny': '0.3.9'},
      );

      expect(drift.rekeyed, hasLength(1));
    });

    test('a dependency with no resolved version still round-trips', () {
      // SDK deps are pinned at 0.0.0 in the lockfile and path/git deps have no
      // version at all; `-` keeps them in the map so adding or dropping one is
      // still visible.
      final drift = diffDependencies(
        projectWith(<String, String>{'riverpod': '3.0.1 direct main'}),
        <String, String>{'riverpod': '3.0.1', 'my_lib': '-'},
      );

      expect(drift.removed.single.describe(), '- my_lib');
    });
  });

  group('withFragmentDrift', () {
    const drift = DependencyDrift(
      changes: <DependencyChange>[],
      recorded: true,
    );

    test('reports the fragments that appeared and disappeared', () {
      final result = withFragmentDrift(
        drift,
        <String>['foundation', 'bloc/v9'],
        <String>['foundation', 'go_router/v18'],
      );

      expect(result.gainedFragments, <String>['go_router/v18']);
      expect(result.lostFragments, <String>['bloc/v9']);
    });

    test('stays quiet without a baseline to compare against', () {
      expect(
        withFragmentDrift(DependencyDrift.unknown, null, <String>[
          'foundation',
        ]).gainedFragments,
        isEmpty,
      );
    });
  });
}
