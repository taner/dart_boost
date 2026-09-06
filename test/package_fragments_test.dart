@TestOn('vm')
library;

import 'dart:io' as io;

import 'package:dart_boost/src/assets/bundled_assets.dart';
import 'package:dart_boost/src/guidelines/composer.dart';
import 'package:dart_boost/src/guidelines/facts.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

/// Composes the *real* bundled tree against synthetic projects.
///
/// `composer_test.dart` covers the layering rules with throwaway fragments;
/// this covers the fragments that actually ship, so a renamed directory or a
/// version key nobody resolves fails here rather than in a user's `CLAUDE.md`.
void main() {
  late FileSystem fs;
  late BundledAssets assets;

  String at(String name) => p.join(fs.currentDirectory.path, name);

  setUp(() {
    fs = memoryFs();
    final root = at('dart_boost');
    final real = io.Directory(p.join(_packageRoot(), 'guidelines'));

    for (final file in real.listSync(recursive: true).whereType<io.File>()) {
      final relative = p.relative(file.path, from: real.path);
      fs.file(p.join(root, 'guidelines', relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(file.readAsStringSync());
    }

    assets = BundledAssets(
      fs.directory(root),
      fs.directory(p.join(root, 'guidelines')),
    );
  });

  /// The composed keys for a Dart-only project resolving exactly [lock].
  ///
  /// Dart-only keeps the expectation to `foundation`, `dart` and the packages
  /// under test -- there is no Flutter or SDK fragment in the way.
  List<String> keysFor(Map<String, String> lock) {
    final project =
        FakeProject(fs, at('app'))
          ..pubspec(
            flutter: false,
            dependencies: {
              for (final name in lock.keys)
                if (lock[name]!.contains('direct main')) name: 'any',
            },
            devDependencies: {
              for (final name in lock.keys)
                if (lock[name]!.contains('direct dev')) name: 'any',
            },
          )
          ..lock(lock);

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

  group('every package fragment path ships', () {
    // One test per fragment path this worker's card is responsible for. A
    // version directory only earns its place where the API genuinely diverged,
    // so this table doubles as the record of which majors that is true for.
    const paths = <String>[
      'go_router/core.md',
      'go_router/14/core.md',
      'go_router/15/core.md',
      'go_router/16/core.md',
      'go_router/17/core.md',
      'go_router/18/core.md',
      'freezed/core.md',
      'freezed/2/core.md',
      'freezed/3/core.md',
      'freezed/4/core.md',
      'json_serializable/core.md',
      'dio/core.md',
      'dio/4/core.md',
      'dio/5/core.md',
      'get_it/core.md',
      'get_it/7/core.md',
      'get_it/8/core.md',
      'get_it/9/core.md',
      'injectable/core.md',
      'injectable/2/core.md',
      'injectable/3/core.md',
    ];

    for (final path in paths) {
      test(path, () {
        final file = io.File(p.join(_packageRoot(), 'guidelines', path));
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        expect(
          file.readAsStringSync().trim(),
          isNotEmpty,
          reason: '$path is empty',
        );
      });
    }
  });

  group('version keys match the majors the resolver sees in the wild', () {
    test('go_router 18 picks the 18 fragment and nothing else', () {
      expect(keysFor({'go_router': '18.0.1 direct main'}), [
        'foundation',
        'dart',
        'go_router/core',
        'go_router/v18',
      ]);
    });

    test('go_router 14 still resolves its own fragment', () {
      expect(
        keysFor({'go_router': '14.8.1 direct main'}),
        contains('go_router/v14'),
      );
    });

    test('freezed 4 picks the 4 fragment, not 3', () {
      final keys = keysFor({
        'freezed': '4.0.1 direct dev',
        'freezed_annotation': '3.1.0 direct main',
      });
      expect(keys, contains('freezed/v4'));
      expect(keys, isNot(contains('freezed/v3')));
    });

    test('dio 5 and dio 4 are distinct fragments', () {
      expect(keysFor({'dio': '5.11.1 direct main'}), contains('dio/v5'));
      expect(keysFor({'dio': '4.0.6 direct main'}), contains('dio/v4'));
    });

    test('get_it 9 picks the 9 fragment', () {
      expect(keysFor({'get_it': '9.2.1 direct main'}), [
        'foundation',
        'dart',
        'get_it/core',
        'get_it/v9',
      ]);
    });

    test('injectable 3 picks the 3 fragment', () {
      expect(
        keysFor({'injectable': '3.0.0 direct main'}),
        contains('injectable/v3'),
      );
    });

    test('a major with no directory contributes only the core fragment', () {
      // json_serializable has one major in the wild, so there is deliberately
      // no version directory -- and the composer must not invent one.
      expect(keysFor({'json_serializable': '6.14.1 direct dev'}), [
        'foundation',
        'dart',
        'json_serializable/core',
      ]);
    });
  });

  group('annotation packages fold into their generator', () {
    test('json_annotation does not version-key json_serializable', () {
      // json_annotation is 4.x while json_serializable is 6.x. Without the
      // priority rule the annotation package would ask for a `4` directory.
      final keys = keysFor({
        'json_serializable': '6.14.1 direct dev',
        'json_annotation': '4.12.0 direct main',
      });
      expect(keys, contains('json_serializable/core'));
      expect(keys, isNot(contains('json_serializable/v4')));
    });

    test('freezed_annotation does not version-key freezed', () {
      final keys = keysFor({
        'freezed': '3.2.4 direct dev',
        'freezed_annotation': '3.1.0 direct main',
      });
      expect(keys, contains('freezed/v3'));
      expect(keys.where((k) => k.startsWith('freezed/')), hasLength(2));
    });

    test('injectable_generator folds into injectable', () {
      final keys = keysFor({
        'injectable': '3.0.0 direct main',
        'injectable_generator': '3.0.0 direct dev',
      });
      expect(keys, contains('injectable/v3'));
      expect(keys, isNot(contains('injectable_generator/core')));
    });

    test('an annotation package alone still gets the generator guidance', () {
      expect(
        keysFor({'json_annotation': '4.12.0 direct main'}),
        contains('json_serializable/core'),
      );
    });
  });

  group('mustBeDirect', () {
    test('a transitive get_it contributes nothing', () {
      expect(keysFor({'get_it': '9.2.1 transitive'}), [
        'foundation',
        'dart',
      ]);
    });

    test('a transitive dio contributes nothing', () {
      expect(keysFor({'dio': '5.11.1 transitive'}), ['foundation', 'dart']);
    });
  });
}

String _packageRoot() {
  var dir = io.Directory.current;
  while (!io.File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    dir = dir.parent;
  }
  return dir.path;
}
