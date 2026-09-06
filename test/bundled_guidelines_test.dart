@TestOn('vm')
library;

import 'dart:io';

import 'package:dart_boost/src/assets/bundled_assets.dart';
import 'package:dart_boost/src/guidelines/facts.dart';
import 'package:dart_boost/src/guidelines/renderer.dart';
import 'package:dart_boost/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Guards the fragments themselves, which no unit test would otherwise read.
void main() {
  test('the bundled tree resolves through resolvePackageUriSync', () async {
    final assets = await BundledAssets.locate();

    expect(assets, isNotNull);
    expect(assets!.guidelines.existsSync(), isTrue);
    expect(assets.fragment('foundation'), isNotNull);
    expect(assets.fragment('nope/nothing'), isNull);
  });

  test(
    'every bundled fragment renders without an unknown flag or variable',
    () async {
      final assets = (await BundledAssets.locate())!;
      const renderer = GuidelineRenderer();

      // Every flag the facts object can name, and every variable, so a typo in a
      // fragment shows up as "unknown" rather than as silently-dropped guidance.
      final variables = <String, String>{
        for (final name in GuidelineFacts.variableNames) name: '<$name>',
      };

      final files = assets.guidelines
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.md');

      expect(files, isNotEmpty);

      for (final file in files) {
        final key = p.relative(file.path, from: assets.guidelines.path);
        final result = renderer.render(
          file.readAsStringSync(),
          flags: const <String>{},
          variables: variables,
          // Only names the facts object actually publishes are acceptable.
          isKnownFlag:
              (name) =>
                  GuidelineFacts.conditionFlags.contains(name) ||
                  RegExp(r'^uses[A-Z]').hasMatch(name),
        );

        expect(
          result.unknownFlags,
          isEmpty,
          reason: '$key branches on an unknown flag',
        );
        expect(
          result.unknownVars,
          isEmpty,
          reason: '$key uses an unknown variable',
        );
        expect(
          result.errors,
          isEmpty,
          reason: '$key has unbalanced directives',
        );
      }
    },
  );

  test('no fragment interpolates a variable inside a fenced code block', () {
    // Fences are masked, always -- a `{{ var }}` in one is emitted literally.
    // Interpolated commands belong in inline code spans.
    final root = Directory(p.join(_packageRoot(), 'guidelines'));
    final offenders = <String>[];

    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (p.extension(file.path) != '.md') continue;
      var inFence = false;
      for (final line in file.readAsLinesSync()) {
        if (RegExp(r'^\s{0,3}(`{3,}|~{3,})').hasMatch(line)) {
          inFence = !inFence;
          continue;
        }
        if (inFence && line.contains(RegExp(r'\{\{\s*\w+\s*\}\}'))) {
          offenders.add('${p.relative(file.path, from: root.path)}: $line');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('the package version constant matches pubspec.yaml', () {
    final pubspec = loadYaml(
      File(p.join(_packageRoot(), 'pubspec.yaml')).readAsStringSync(),
    );
    expect(packageVersion, (pubspec as Map)['version']);
  });

  test('.gitignore does not exclude the guidelines tree', () {
    // `dart pub publish` honours .gitignore. `tool/verify_assets.dart` is the
    // authoritative check; this one fails faster and says why.
    final gitignore = File(p.join(_packageRoot(), '.gitignore'));
    if (!gitignore.existsSync()) return;
    for (final line in gitignore.readAsLinesSync()) {
      final entry = line.split('#').first.trim();
      if (entry.isEmpty) continue;
      expect(
        entry.replaceAll('/', ''),
        isNot('guidelines'),
        reason:
            'excluding guidelines/ produces a release that composes nothing',
      );
    }
  });
}

String _packageRoot() {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    dir = dir.parent;
  }
  return dir.path;
}
