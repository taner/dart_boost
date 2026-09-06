import 'package:dart_boost/src/project/package_ref.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/project/workspace.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late ProjectResolver resolver;

  setUp(() {
    fs = memoryFs();
    resolver = ProjectResolver(
      fileSystem: fs,
      processRunner: FakeProcessRunner(),
    );
  });

  String root(String name) => p.join(fs.currentDirectory.path, name);

  group('dependency classification', () {
    test('prefers package_graph.json, which names direct deps explicitly', () {
      final project =
          FakeProject(fs, root('app'))
            ..pubspec(dependencies: {'riverpod': '^2.6.0'})
            ..lock({
              'riverpod': '2.6.1 direct main',
              'meta': '1.15.0 transitive',
              'build_runner': '2.4.0 direct dev',
            })
            ..packageGraph(
              rootName: 'my_app',
              dependencies: ['riverpod'],
              devDependencies: ['build_runner'],
            );

      final resolved = resolver.resolve(project.root);

      expect(resolved.dependencySource, '.dart_tool/package_graph.json');
      expect(resolved.packages['riverpod']!.kind, DependencyKind.directMain);
      expect(resolved.packages['build_runner']!.kind, DependencyKind.directDev);
      expect(resolved.packages['meta']!.kind, DependencyKind.transitive);
    });

    test('falls back to the lockfile, parsed as YAML', () {
      // `transitive` is unquoted in a real lockfile while the others are
      // quoted, so this must not be a string match on raw lines.
      final project =
          FakeProject(fs, root('app'))
            ..pubspec(dependencies: {'dio': '^5.0.0'})
            ..lock({
              'dio': '5.4.0 direct main',
              'http_parser': '4.0.2 transitive',
              'lints': '5.0.0 direct dev',
              'intl': '0.19.0 direct overridden',
            });

      final resolved = resolver.resolve(project.root);

      expect(resolved.dependencySource, 'pubspec.lock');
      expect(resolved.packages['dio']!.kind, DependencyKind.directMain);
      expect(resolved.packages['http_parser']!.isDirect, isFalse);
      expect(resolved.packages['lints']!.isDev, isTrue);
      // An overridden dependency is still one the user chose.
      expect(resolved.packages['intl']!.isDirect, isTrue);
    });

    test('falls back to pubspec.yaml when there is no lock', () {
      final project = FakeProject(fs, root('app'))
        ..pubspec(flutter: false, dependencies: {'args': '^2.4.0'});

      final resolved = resolver.resolve(project.root);

      expect(resolved.dependencySource, 'pubspec.yaml');
      expect(resolved.packages['args']!.isDirect, isTrue);
    });

    test('carries resolved versions and version keys', () {
      final project =
          FakeProject(fs, root('app'))
            ..pubspec(dependencies: {'riverpod': '^2.6.0'})
            ..lock({
              'riverpod': '2.6.1 direct main',
              'wobble': '0.4.2 direct main',
            });

      final resolved = resolver.resolve(project.root);

      expect(resolved.packages['riverpod']!.version, Version.parse('2.6.1'));
      expect(resolved.packages['riverpod']!.versionKey, '2');
      expect(resolved.packages['wobble']!.versionKey, '0.4');
    });

    test('hasPackage honours a constraint', () {
      final project =
          FakeProject(fs, root('app'))
            ..pubspec(dependencies: {'go_router': '^16.0.0'})
            ..lock({'go_router': '16.2.4 direct main'});

      final resolved = resolver.resolve(project.root);

      expect(resolved.hasPackage('go_router'), isTrue);
      expect(resolved.hasPackage('go_router', '^16.0.0'), isTrue);
      expect(resolved.hasPackage('go_router', '^14.0.0'), isFalse);
      expect(resolved.hasPackage('nope'), isFalse);
      expect(resolved.packageMajor('go_router'), 16);
    });
  });

  group('flutter detection', () {
    test('detects a Flutter project from the dependency', () {
      final project = FakeProject(fs, root('app'))..pubspec();
      expect(resolver.resolve(project.root).isFlutterProject, isTrue);
    });

    test('a plain Dart package is not a Flutter project', () {
      final project = FakeProject(fs, root('cli'))
        ..pubspec(flutter: false, dependencies: {'args': '^2.4.0'});
      expect(resolver.resolve(project.root).isFlutterProject, isFalse);
    });
  });

  group('workspaces', () {
    test('single package', () {
      final project = FakeProject(fs, root('app'))..pubspec();
      final resolved = resolver.resolve(project.root);
      expect(resolved.workspace.kind, WorkspaceKind.single);
      expect(resolved.root.path, project.root.path);
    });

    test(
      'pub workspace writes at the workspace root, reads at the config root',
      () {
        FakeProject(fs, root('repo'))
          ..write('pubspec.yaml', 'name: repo\nworkspace:\n  - packages/app\n')
          ..packageConfig()
          ..dartToolVersion('3.47.2');
        final member = FakeProject(fs, root(p.join('repo', 'packages', 'app')))
          ..write('pubspec.yaml', 'name: app\nresolution: workspace\n');

        final resolved = resolver.resolve(member.root);

        expect(resolved.workspace.kind, WorkspaceKind.pubWorkspace);
        expect(resolved.root.path, root('repo'));
        expect(resolved.analysisRoot.path, root('repo'));
        expect(resolved.workspace.members, ['packages/app']);
      },
    );

    test('melos writes at the repository root', () {
      FakeProject(fs, root('mono'))
        ..write('melos.yaml', 'name: mono\npackages:\n  - packages/*\n')
        ..write('pubspec.yaml', 'name: mono\n');
      final member =
          FakeProject(fs, root(p.join('mono', 'packages', 'core')))
            ..pubspec(name: 'core', flutter: false)
            ..packageConfig();

      final resolved = resolver.resolve(member.root);

      expect(resolved.workspace.kind, WorkspaceKind.melos);
      expect(resolved.root.path, root('mono'));
      // Reads still come from the member, which owns the resolution.
      expect(resolved.analysisRoot.path, member.root.path);
      expect(resolved.workspace.members, ['packages/*']);
    });

    test('a directory with no pubspec anywhere above it is implicit', () {
      final dir = fs.directory(root('loose'))..createSync(recursive: true);
      expect(resolver.resolve(dir).workspace.kind, WorkspaceKind.implicit);
    });
  });

  test('records on-disk package roots from package_config.json', () {
    final vendor = fs.directory(root('vendor_pkg'))
      ..createSync(recursive: true);
    final project =
        FakeProject(fs, root('app'))
          ..pubspec(dependencies: {'vendor_pkg': '^1.0.0'})
          ..lock({'vendor_pkg': '1.0.0 direct main'})
          ..packageConfig(packages: {'vendor_pkg': vendor.path});

    final resolved = resolver.resolve(project.root);

    expect(resolved.packages['vendor_pkg']!.rootPath, vendor.path);
  });

  test('a malformed lockfile is a warning, not a crash', () {
    final project =
        FakeProject(fs, root('app'))
          ..pubspec()
          ..write('pubspec.lock', 'packages:\n  - this is: not: valid\n');

    final resolved = resolver.resolve(project.root);

    expect(resolved.warnings, isNotEmpty);
    expect(resolved.isFlutterProject, isTrue);
  });

  test('a directory with no pubspec.yaml at all warns', () {
    // Nothing downstream fails on this -- the composer still emits the
    // unconditional fragments and the writers still create their files -- so
    // without a warning, `install` run from the wrong directory reports
    // success while describing a project that is not there.
    final dir = fs.directory(root('somewhere'))..createSync(recursive: true);

    final resolved = resolver.resolve(dir);

    expect(resolved.pubspec, isNull);
    expect(
      resolved.warnings,
      contains(allOf(contains('No pubspec.yaml'), contains('-C <path>'))),
    );
  });
}
