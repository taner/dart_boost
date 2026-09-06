import 'package:dart_boost/src/assets/bundled_assets.dart';
import 'package:dart_boost/src/guidelines/composer.dart';
import 'package:dart_boost/src/guidelines/facts.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late BundledAssets assets;

  String at(String name) => p.join(fs.currentDirectory.path, name);

  void fragment(String key, String content) {
    fs.file(
        '${p.joinAll([at('dart_boost'), 'guidelines', ...key.split('/')])}.md',
      )
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    fs = memoryFs();
    fs
        .directory(p.join(at('dart_boost'), 'guidelines'))
        .createSync(recursive: true);
    assets = BundledAssets(
      fs.directory(at('dart_boost')),
      fs.directory(p.join(at('dart_boost'), 'guidelines')),
    );
  });

  ComposeResult compose(
    Project project, {
    List<String> trusted = const <String>[],
    Set<String> exclude = const <String>{},
  }) =>
      GuidelineComposer(
        fileSystem: fs,
        assets: assets,
        project: project,
        facts: GuidelineFacts.forProject(project),
        trustedThirdParty: trusted,
        excludeKeys: exclude,
      ).compose();

  Project resolve(FakeProject project) => ProjectResolver(
    fileSystem: fs,
    processRunner: FakeProcessRunner(),
  ).resolve(project.root);

  group('layering', () {
    test('core, then conditional, then packages, in that order', () {
      fragment('foundation', '# Foundation\nalways');
      fragment('dart/core', '# Dart\nalways');
      fragment('flutter/core', '# Flutter\nflutter only');
      fragment('flutter/3.47/core', '# Flutter 3.47\nsdk keyed');
      fragment('riverpod/core', '# Riverpod\nany version');
      fragment('riverpod/3/core', '# Riverpod 3\nv3 only');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec(dependencies: {'riverpod': '^3.0.0'})
            ..lock({'riverpod': '3.0.1 direct main'})
            ..dartToolVersion('3.47.2');

      final result = compose(resolve(project));

      expect(result.keys, [
        'foundation',
        'dart',
        'flutter',
        'flutter/v3.47',
        'riverpod/core',
        'riverpod/v3',
      ]);
      expect(result.content, contains('=== riverpod/v3 rules ==='));
    });

    test(
      'a missing version directory contributes nothing -- no nearest match',
      () {
        // Boost makes the same call deliberately: no range matching and no
        // fallback to a lower version. Predictability over cleverness.
        fragment('riverpod/core', '# Riverpod\nany');
        fragment('riverpod/2/core', '# Riverpod 2\nv2');

        final project =
            FakeProject(fs, at('app'))
              ..pubspec(flutter: false, dependencies: {'riverpod': '^3.0.0'})
              ..lock({'riverpod': '3.0.1 direct main'});

        expect(compose(resolve(project)).keys, ['riverpod/core']);
      },
    );

    test('an SDK minor picks its own fragment and no other', () {
      // Two SDK-keyed fragments now ship, and they contradict each other on
      // purpose (what 3.47 added is what 3.44 lacks). Composing both, or
      // composing the wrong one, is worse than composing neither.
      fragment('flutter/core', '# Flutter\nany');
      fragment('flutter/3.44/core', '# Flutter 3.44\nolder');
      fragment('flutter/3.47/core', '# Flutter 3.47\nnewer');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec()
            ..lock({})
            ..dartToolVersion('3.44.9');

      final result = compose(resolve(project));

      expect(result.keys, contains('flutter/v3.44'));
      expect(result.keys, isNot(contains('flutter/v3.47')));
      expect(result.content, isNot(contains('newer')));
    });

    test('picks up every other .md under the matched version directory', () {
      fragment('riverpod/3/core', '# Riverpod 3');
      fragment('riverpod/3/testing', '# Riverpod 3 testing');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec(flutter: false, dependencies: {'riverpod': '^3.0.0'})
            ..lock({'riverpod': '3.0.1 direct main'});

      expect(compose(resolve(project)).keys, [
        'riverpod/v3',
        'riverpod/v3/testing',
      ]);
    });

    test('the 0.x minor is the key', () {
      fragment('wobble/0.4/core', '# Wobble 0.4');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec(flutter: false, dependencies: {'wobble': '^0.4.0'})
            ..lock({'wobble': '0.4.2 direct main'});

      expect(compose(resolve(project)).keys, ['wobble/v0.4']);
    });

    test('an excluded key is dropped', () {
      fragment('foundation', '# Foundation');
      fragment('dart/core', '# Dart');

      final project = FakeProject(fs, at('app'))..pubspec(flutter: false);

      expect(compose(resolve(project), exclude: {'dart'}).keys, ['foundation']);
    });

    test('an empty fragment contributes no section', () {
      fragment('foundation', '# Foundation');
      fragment(
        'dart/core',
        '<!--boost:if usesNothingAtAll-->\nhidden\n<!--boost:end-->',
      );

      final project = FakeProject(fs, at('app'))..pubspec(flutter: false);

      expect(compose(resolve(project)).keys, ['foundation']);
    });
  });

  group('package selection', () {
    test('mustBeDirect skips a transitive-only match', () {
      fragment('dio/core', '# Dio');

      final direct =
          FakeProject(fs, at('direct'))
            ..pubspec(flutter: false, dependencies: {'dio': '^5.0.0'})
            ..lock({'dio': '5.4.0 direct main'});
      expect(compose(resolve(direct)).keys, ['dio/core']);

      final transitive =
          FakeProject(fs, at('transitive'))
            ..pubspec(flutter: false)
            ..lock({'dio': '5.4.0 transitive'});
      expect(compose(resolve(transitive)).keys, isEmpty);
    });

    test('a binding package supplies the version key for the family', () {
      // `flutter_riverpod` beats `riverpod` in the priority table, and the
      // alias points both at one directory -- so the specific package decides
      // the version and the shared guidance is still emitted.
      fragment('riverpod/core', '# Riverpod');
      fragment('riverpod/3/core', '# Riverpod 3');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec(dependencies: {'flutter_riverpod': '^3.0.0'})
            ..lock({
              'flutter_riverpod': '3.0.1 direct main',
              'riverpod': '3.0.1 transitive',
            });

      expect(compose(resolve(project)).keys, ['riverpod/core', 'riverpod/v3']);
    });

    test('the SDK-pinned flutter package never produces a 0.0 key', () {
      fragment('flutter/core', '# Flutter');
      final project =
          FakeProject(fs, at('app'))
            ..pubspec()
            ..lock({'flutter': '0.0.0 direct main'});

      expect(compose(resolve(project)).keys, ['flutter']);
    });
  });

  group('user overrides', () {
    test('an override replaces the bundled fragment in place', () {
      fragment('foundation', '# Foundation\nbundled');
      fragment('dart/core', '# Dart\nbundled');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec(flutter: false)
            ..write('.ai/guidelines/dart/core.md', '# Dart\nmine');

      final result = compose(resolve(project));

      expect(result.keys, ['foundation', 'dart']);
      expect(result.content, contains('# Dart\n\nmine'));
      expect(result.content, isNot(contains('# Dart\n\nbundled')));
      expect(result.fragments.last.custom, isTrue);
    });

    test('a user file matching no bundled key lands first', () {
      fragment('foundation', '# Foundation\nbundled');

      final project =
          FakeProject(fs, at('app'))
            ..pubspec(flutter: false)
            ..write('.ai/guidelines/house-style.md', '# House style\nours');

      final result = compose(resolve(project));

      expect(result.keys, ['.ai/house-style', 'foundation']);
      expect(
        result.content.indexOf('House style'),
        lessThan(result.content.indexOf('Foundation')),
      );
    });
  });

  group('third-party fragments', () {
    late FakeProject project;
    late Directory vendor;

    setUp(() {
      vendor = fs.directory(at('serverpod_pkg'))..createSync(recursive: true);
      fs.file(p.join(vendor.path, 'guidelines', 'core.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('# Serverpod\nvendor guidance');

      project =
          FakeProject(fs, at('app'))
            ..pubspec(flutter: false, dependencies: {'serverpod': '^2.0.0'})
            ..lock({'serverpod': '2.1.0 direct main'})
            ..packageConfig(packages: {'serverpod': vendor.path});
    });

    test('nothing is read without explicit opt-in', () {
      final result = compose(resolve(project));

      expect(result.keys, isEmpty);
      expect(result.untrustedThirdParty, ['serverpod']);
    });

    test(
      'an opted-in package contributes, keyed by package and relative path',
      () {
        final result = compose(resolve(project), trusted: ['serverpod']);

        expect(result.keys, ['serverpod/core']);
        expect(result.content, contains('vendor guidance'));
        expect(result.fragments.single.thirdParty, isTrue);
      },
    );

    test(
      'a fragment declaring a newer facts contract is skipped with a warning',
      () {
        fs
            .file(p.join(vendor.path, 'guidelines', 'manifest.yaml'))
            .writeAsStringSync('boost_facts_version: 99\n');

        final result = compose(resolve(project), trusted: ['serverpod']);

        expect(result.keys, isEmpty);
        expect(result.warnings.single, contains('facts version 99'));
      },
    );

    test('transitive dependencies are never scanned', () {
      final transitiveProject =
          FakeProject(fs, at('app2'))
            ..pubspec(flutter: false)
            ..lock({'serverpod': '2.1.0 transitive'})
            ..packageConfig(packages: {'serverpod': vendor.path});

      final result = compose(
        resolve(transitiveProject),
        trusted: ['serverpod'],
      );

      expect(result.keys, isEmpty);
      expect(result.untrustedThirdParty, isEmpty);
    });
  });

  group('degradation', () {
    test('a bad fragment omits itself and warns rather than aborting', () {
      fragment('foundation', '# Foundation\nfine');
      fragment(
        'dart/core',
        '# Dart\n{{ nonsense }} and <!--boost:if typo3-->x',
      );

      final project = FakeProject(fs, at('app'))..pubspec(flutter: false);
      final result = compose(resolve(project));

      expect(result.keys, containsAll(<String>['foundation', 'dart']));
      expect(result.warnings, isNotEmpty);
      expect(result.content, contains('{{ nonsense }}'));
    });
  });

  test(
    'sections are separated so a human can see where guidance came from',
    () {
      fragment('foundation', '# Foundation\nbody');
      final project = FakeProject(fs, at('app'))..pubspec(flutter: false);

      expect(
        compose(resolve(project)).content,
        '=== foundation rules ===\n\n# Foundation\n\nbody\n',
      );
    },
  );
}
