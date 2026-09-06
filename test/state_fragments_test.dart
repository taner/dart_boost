@TestOn('vm')
library;

import 'package:dart_boost/src/assets/bundled_assets.dart';
import 'package:dart_boost/src/guidelines/composer.dart';
import 'package:dart_boost/src/guidelines/facts.dart';
import 'package:dart_boost/src/project/package_registry.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:test/test.dart';

import 'support/fake_project.dart';

/// Covers the state-management corner of the fragment tree end to end: the
/// files exist, the registry routes every member of each family at them, and a
/// project on one major never picks up the other major's guidance.
///
/// The fragment tree has no fallback to a nearest-lower version, so "the
/// directory is named `9` and the resolver produced `9`" is the whole
/// contract -- and it is exactly the sort of thing a rename breaks silently.
void main() {
  late BundledAssets assets;
  late FileSystem fs;

  setUpAll(() async {
    final located = await BundledAssets.locate();
    expect(located, isNotNull, reason: 'the bundled tree must resolve');
    assets = located!;
  });

  setUp(() => fs = memoryFs());

  /// Composes against the *real* bundled tree, with the project itself faked.
  List<String> keysFor(FakeProject project) {
    final resolved = ProjectResolver(
      fileSystem: fs,
      processRunner: FakeProcessRunner(),
    ).resolve(project.root);
    return GuidelineComposer(
      fileSystem: fs,
      assets: assets,
      project: resolved,
      facts: GuidelineFacts.forProject(resolved),
    ).compose().keys;
  }

  FakeProject appWith(
    Map<String, String> dependencies,
    Map<String, String> lock, {
    bool flutter = true,
  }) =>
      FakeProject(fs, '/app')
        ..pubspec(flutter: flutter, dependencies: dependencies)
        ..lock(lock);

  group('the fragments exist', () {
    const expected = <String>[
      'riverpod/core',
      'riverpod/2/core',
      'riverpod/2/testing',
      'riverpod/3/core',
      'riverpod/3/testing',
      'bloc/core',
      'bloc/7/core',
      'bloc/8/core',
      'bloc/9/core',
    ];

    for (final key in expected) {
      test('guidelines/$key.md is bundled and non-empty', () {
        final file = assets.fragment(key);
        expect(file, isNotNull, reason: 'guidelines/$key.md is missing');
        expect(file!.readAsStringSync().trim(), isNotEmpty);
      });
    }

    test('no version directory exists without a core.md in it', () {
      // `fragmentsIn` only contributes the non-core siblings, so a version
      // directory holding only `testing.md` would emit guidance with no
      // statement of which major it is for.
      for (final dir in <String>['riverpod', 'bloc']) {
        for (final version
            in assets.guidelines
                .childDirectory(dir)
                .listSync()
                .whereType<Directory>()) {
          expect(
            assets.fragment('$dir/${version.basename}/core'),
            isNotNull,
            reason: '$dir/${version.basename} has no core.md',
          );
        }
      }
    });
  });

  group('riverpod routing', () {
    test('a riverpod 3 app gets only the v3 fragments', () {
      final keys = keysFor(
        appWith(
          {'flutter_riverpod': '^3.0.0'},
          {
            'flutter_riverpod': '3.4.3 direct main',
            'riverpod': '3.4.3 transitive',
          },
        ),
      );

      expect(keys, containsAll(<String>['riverpod/core', 'riverpod/v3']));
      expect(keys, contains('riverpod/v3/testing'));
      expect(keys.where((k) => k.startsWith('riverpod/v2')), isEmpty);
    });

    test('a riverpod 2 app gets only the v2 fragments', () {
      final keys = keysFor(
        appWith(
          {'hooks_riverpod': '^2.6.0'},
          {
            'hooks_riverpod': '2.6.1 direct main',
            'flutter_riverpod': '2.6.1 transitive',
            'riverpod': '2.6.1 transitive',
          },
        ),
      );

      expect(
        keys,
        containsAll(<String>[
          'riverpod/core',
          'riverpod/v2',
          'riverpod/v2/testing',
        ]),
      );
      expect(keys.where((k) => k.startsWith('riverpod/v3')), isEmpty);
    });
  });

  group('bloc routing', () {
    test('flutter_bloc supplies the version key for the bloc tree', () {
      final keys = keysFor(
        appWith(
          {'flutter_bloc': '^9.1.0'},
          {'flutter_bloc': '9.1.1 direct main', 'bloc': '9.2.1 transitive'},
        ),
      );

      expect(keys, containsAll(<String>['bloc/core', 'bloc/v9']));
      expect(keys.where((k) => k.startsWith('bloc/v8')), isEmpty);
      expect(keys.where((k) => k.startsWith('bloc/v7')), isEmpty);
    });

    test('a bloc 8 app gets the bloc 8 fragment', () {
      final keys = keysFor(
        appWith(
          {'flutter_bloc': '^8.1.0'},
          {'flutter_bloc': '8.1.6 direct main', 'bloc': '8.1.4 transitive'},
        ),
      );

      expect(keys, containsAll(<String>['bloc/core', 'bloc/v8']));
      expect(keys.where((k) => k.startsWith('bloc/v9')), isEmpty);
    });

    test('a dart-only bloc 7 app still gets a version fragment', () {
      final keys = keysFor(
        appWith(
          {'bloc': '^7.2.0'},
          {'bloc': '7.2.1 direct main'},
          flutter: false,
        ),
      );

      expect(keys, containsAll(<String>['bloc/core', 'bloc/v7']));
    });

    test(
      'hydrated_bloc does not hijack the version key with its own major',
      () {
        // `hydrated_bloc` 11 pairs with `bloc` 9. Aliasing it onto the `bloc`
        // directory the way `flutter_bloc` is aliased would ask for
        // `bloc/11/core.md` and emit no version guidance at all.
        final keys = keysFor(
          appWith(
            {'hydrated_bloc': '^11.0.0'},
            {'hydrated_bloc': '11.0.0 direct main', 'bloc': '9.2.1 transitive'},
            flutter: false,
          ),
        );

        expect(keys, containsAll(<String>['bloc/core', 'bloc/v9']));
        expect(keys.where((k) => k.startsWith('bloc/v11')), isEmpty);
      },
    );

    test(
      'the hydrated_bloc section renders only when the package is there',
      () {
        final withIt = keysFor(
          appWith(
            {'flutter_bloc': '^9.0.0', 'hydrated_bloc': '^11.0.0'},
            {
              'flutter_bloc': '9.1.1 direct main',
              'hydrated_bloc': '11.0.0 direct main',
              'bloc': '9.2.1 transitive',
            },
          ),
        );
        expect(withIt, contains('bloc/v9'));

        // The flag itself is what the fragment branches on.
        final project = ProjectResolver(
          fileSystem: fs,
          processRunner: FakeProcessRunner(),
        ).resolve(fs.directory('/app'));
        expect(
          GuidelineFacts.forProject(project).hasFlag('usesHydratedBloc'),
          isTrue,
        );
      },
    );
  });

  group('registry', () {
    test('the whole riverpod family points at one directory', () {
      for (final name in <String>[
        'riverpod',
        'flutter_riverpod',
        'hooks_riverpod',
      ]) {
        expect(PackageRegistry.guidelineName(name), 'riverpod');
      }
    });

    test('flutter_bloc aliases onto bloc and hydrated_bloc does not', () {
      expect(PackageRegistry.guidelineName('flutter_bloc'), 'bloc');
      expect(PackageRegistry.guidelineName('bloc'), 'bloc');
      expect(PackageRegistry.guidelineName('hydrated_bloc'), 'hydrated_bloc');
      expect(PackageRegistry.priorities['hydrated_bloc'], isNull);
    });
  });
}
