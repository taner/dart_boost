import 'package:dart_boost/src/project/sdk_versions.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;

  setUp(() => fs = memoryFs());

  String at(String name) => p.join(fs.currentDirectory.path, name);

  SdkResolver resolverWith(ProcessRunner runner, {bool probe = false}) =>
      SdkResolver(
        fileSystem: fs,
        processRunner: runner,
        allowProcessProbe: probe,
      );

  void writeFlutterSdk(
    String root, {
    required String framework,
    required String dart,
  }) {
    fs.file(p.join(root, 'bin', 'cache', 'flutter.version.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
{
  "frameworkVersion": "$framework",
  "channel": "stable",
  "dartSdkVersion": "$dart"
}
''');
  }

  test('reads .dart_tool/version first -- the cheapest accurate signal', () {
    final project = FakeProject(fs, at('app'))..dartToolVersion('3.47.2');

    final sdk = resolverWith(
      FakeProcessRunner(),
    ).resolve(projectRoot: project.root);

    expect(sdk.flutter, Version.parse('3.47.2'));
    expect(sdk.flutterSource, '.dart_tool/version');
    expect(sdk.flutterKey, '3.47');
  });

  test('falls back to the FVM 3 pin when it names a version', () {
    final project = FakeProject(fs, at('app'))
      ..write('.fvmrc', '{"flutter": "3.44.9"}');

    final sdk = resolverWith(
      FakeProcessRunner(),
    ).resolve(projectRoot: project.root);

    expect(sdk.flutter, Version.parse('3.44.9'));
    expect(sdk.flutterSource, '.fvmrc');
    expect(sdk.usesFvm, isTrue);
    expect(sdk.fvmPin, '3.44.9');
  });

  test('falls back to the FVM 2 config', () {
    final project = FakeProject(fs, at('app'))..write(
      '.fvm/fvm_config.json',
      '{"flutterSdkVersion": "3.7.7", "flavors": {}}',
    );

    final sdk = resolverWith(
      FakeProcessRunner(),
    ).resolve(projectRoot: project.root);

    expect(sdk.flutter, Version.parse('3.7.7'));
    expect(sdk.flutterSource, '.fvm/fvm_config.json');
    expect(sdk.usesFvm, isTrue);
  });

  test(
    'a channel pin is not a version, so it resolves through the SDK cache',
    () {
      // `.fvmrc` legitimately contains `{"flutter": "stable"}`.
      writeFlutterSdk(at('sdks/stable'), framework: '3.47.2', dart: '3.13.2');
      final project = FakeProject(fs, at('app'))
        ..write('.fvmrc', '{"flutter": "stable"}');
      fs.directory(p.join(project.path, '.fvm')).createSync(recursive: true);
      fs
          .link(p.join(project.path, '.fvm', 'flutter_sdk'))
          .createSync(at('sdks/stable'));

      final sdk = resolverWith(
        FakeProcessRunner(),
      ).resolve(projectRoot: project.root);

      expect(sdk.flutter, Version.parse('3.47.2'));
      expect(sdk.flutterSource, '.fvm/flutter_sdk');
      expect(sdk.fvmPin, 'stable');
      expect(sdk.channel, 'stable');
    },
  );

  test('derives the SDK root from the flutter package and reads its cache', () {
    writeFlutterSdk(at('flutter_sdk'), framework: '3.44.9', dart: '3.12.2');
    final project = FakeProject(fs, at('app'));

    final sdk = resolverWith(FakeProcessRunner()).resolve(
      projectRoot: project.root,
      // `<sdk>/packages/flutter` is what package_config.json records.
      flutterPackagePath: p.join(at('flutter_sdk'), 'packages', 'flutter'),
    );

    expect(sdk.flutter, Version.parse('3.44.9'));
    expect(sdk.flutterSource, 'flutter.version.json');
    expect(sdk.dart, Version.parse('3.12.2'));
  });

  test('the Dart version comes from the SDK that actually ran pub get', () {
    final project = FakeProject(fs, at('app'))..dartToolVersion('3.47.2');

    final sdk = resolverWith(FakeProcessRunner()).resolve(
      projectRoot: project.root,
      packageConfigGeneratorVersion: '3.10.7',
    );

    expect(sdk.dart, Version.parse('3.10.7'));
    expect(sdk.dartSource, 'package_config.json generatorVersion');
  });

  group('the toolchain probe', () {
    final runner = FakeProcessRunner({
      'flutter --version --machine': const ProcessOutcome(
        0,
        '{"frameworkVersion": "3.47.2", "channel": "beta", "dartSdkVersion": "3.13.2"}',
        '',
      ),
    });

    test('is not spawned unless it was allowed', () {
      final project = FakeProject(fs, at('app'));
      final warnings = <String>[];
      final sdk = SdkResolver(
        fileSystem: fs,
        processRunner: runner,
        onWarning: warnings.add,
      ).resolve(
        projectRoot: project.root,
        flutterPackagePath: p.join(at('nowhere'), 'packages', 'flutter'),
      );

      expect(sdk.flutter, isNull);
      expect(warnings.single, contains('--probe-sdk'));
      expect(runner.invocations, isEmpty);
    });

    test('answers when it is allowed', () {
      final project = FakeProject(fs, at('app'));
      final sdk = resolverWith(runner, probe: true).resolve(
        projectRoot: project.root,
        flutterPackagePath: p.join(at('nowhere'), 'packages', 'flutter'),
      );

      expect(sdk.flutter, Version.parse('3.47.2'));
      expect(sdk.channel, 'beta');
      expect(sdk.dart, Version.parse('3.13.2'));
    });
  });

  test('a malformed FVM config is a warning, not a crash', () {
    final warnings = <String>[];
    final project = FakeProject(fs, at('app'))..write('.fvmrc', 'not json');

    final sdk = SdkResolver(
      fileSystem: fs,
      processRunner: FakeProcessRunner(),
      onWarning: warnings.add,
    ).resolve(projectRoot: project.root);

    expect(sdk.flutter, isNull);
    expect(warnings.single, contains('.fvmrc'));
  });
}
