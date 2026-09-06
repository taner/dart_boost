import 'package:dart_boost/src/guidelines/facts.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;

  setUp(() => fs = memoryFs());

  String at(String name) => p.join(fs.currentDirectory.path, name);

  GuidelineFacts factsFor(FakeProject project) => GuidelineFacts.forProject(
    ProjectResolver(
      fileSystem: fs,
      processRunner: FakeProcessRunner(),
    ).resolve(project.root),
  );

  test('emits a flag per package and per resolved version key', () {
    final facts = factsFor(
      FakeProject(fs, at('app'))
        ..pubspec(flutter: false, dependencies: {'riverpod': '^3.0.0'})
        ..lock({'riverpod': '3.0.1 direct main', 'wobble': '0.4.2 transitive'}),
    );

    expect(facts.flags, containsAll(<String>['usesRiverpod', 'usesRiverpod3']));
    expect(facts.flags, isNot(contains('usesRiverpod2')));
    // A 0.x key becomes a single token so `usesWobble0_4` stays parseable.
    expect(facts.flags, contains('usesWobble0_4'));
  });

  test('condition flags are a closed set, so a typo is caught', () {
    final facts = factsFor(FakeProject(fs, at('app'))..pubspec(flutter: false));

    expect(facts.isKnownFlag('isFlutterProject'), isTrue);
    expect(facts.hasFlag('isFlutterProject'), isFalse);
    expect(facts.isKnownFlag('isFlutterProjekt'), isFalse);
  });

  test('package flags are an open set, so an absent package is just false', () {
    // A fragment legitimately asks about `usesRiverpodGenerator` in a project
    // that does not have it. Reporting that as a typo would make every real
    // fragment noisy.
    final facts = factsFor(FakeProject(fs, at('app'))..pubspec(flutter: false));

    expect(facts.isKnownFlag('usesRiverpodGenerator'), isTrue);
    expect(facts.hasFlag('usesRiverpodGenerator'), isFalse);
  });

  test('the project is not a dependency of itself', () {
    final facts = factsFor(
      FakeProject(fs, at('app'))
        ..pubspec(name: 'my_app', flutter: false)
        ..packageConfig(packages: {'my_app': at('app')}),
    );

    expect(facts.flags, isNot(contains('usesMyApp')));
    expect(facts.project.packages.keys, isNot(contains('my_app')));
  });

  test('the invocation prefix follows FVM', () {
    final plain = factsFor(FakeProject(fs, at('plain'))..pubspec());
    expect(plain.variables['sdkCommand'], 'flutter');
    expect(plain.variables['dartRunCommand'], 'dart run');

    final pinned = factsFor(
      FakeProject(fs, at('pinned'))
        ..pubspec()
        ..write('.fvmrc', '{"flutter": "3.47.2"}'),
    );
    expect(pinned.variables['sdkCommand'], 'fvm flutter');
    expect(pinned.variables['dartRunCommand'], 'fvm dart run');
    expect(pinned.variables['testCommand'], 'fvm flutter test');
  });

  test('a Dart-only project gets dart commands, not flutter ones', () {
    final facts = factsFor(FakeProject(fs, at('cli'))..pubspec(flutter: false));

    expect(facts.hasFlag('isDartOnlyProject'), isTrue);
    expect(facts.variables['sdkCommand'], 'dart');
    expect(facts.variables['testCommand'], 'dart test');
  });

  test('the melos prefix is empty rather than absent outside a monorepo', () {
    // Fragments can then write `{{workspacePrefix}}dart test` unconditionally.
    final facts = factsFor(FakeProject(fs, at('app'))..pubspec(flutter: false));
    expect(facts.variables['workspacePrefix'], '');
  });

  test('melos supplies the workspace prefix', () {
    FakeProject(fs, at('mono'))
      ..write('melos.yaml', 'name: mono\npackages:\n  - packages/*\n')
      ..write('pubspec.yaml', 'name: mono\n');
    final member = FakeProject(fs, at(p.join('mono', 'packages', 'core')))
      ..pubspec(name: 'core', flutter: false);

    final facts = factsFor(member);

    expect(facts.hasFlag('isMelosWorkspace'), isTrue);
    expect(facts.variables['workspacePrefix'], 'melos exec -- ');
  });

  test('the declared variable vocabulary is exactly what is produced', () {
    // Third-party fragments declare against `variableNames`, so it must not
    // drift from what the facts object actually emits.
    final facts = factsFor(FakeProject(fs, at('app'))..pubspec(flutter: false));

    expect(facts.variables.keys.toSet(), GuidelineFacts.variableNames);
    for (final name in GuidelineFacts.variableNames) {
      expect(facts.variables[name], isNotNull, reason: name);
    }
  });

  test('usesCodegen only fires for a direct build_runner', () {
    final direct = factsFor(
      FakeProject(fs, at('direct'))
        ..pubspec(flutter: false, devDependencies: {'build_runner': '^2.4.0'})
        ..lock({'build_runner': '2.4.9 direct dev'}),
    );
    expect(direct.hasFlag('usesCodegen'), isTrue);

    final transitive = factsFor(
      FakeProject(fs, at('transitive'))
        ..pubspec(flutter: false)
        ..lock({'build_runner': '2.4.9 transitive'}),
    );
    expect(transitive.hasFlag('usesCodegen'), isFalse);
  });
}
