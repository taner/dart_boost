import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

import '../util/process_runner.dart';
import '../util/version_key.dart';
import 'package_ref.dart';
import 'sdk_versions.dart';
import 'workspace.dart';

/// Everything dart_boost knows about the target project.
class Project {
  const Project({
    required this.workspace,
    required this.packages,
    required this.sdk,
    required this.isFlutterProject,
    this.name,
    this.pubspec,
    this.packageConfigPath,
    this.dependencySource = 'pubspec.yaml',
    this.warnings = const <String>[],
  });

  final WorkspaceInfo workspace;

  /// Every resolved dependency, keyed by package name.
  final Map<String, PackageRef> packages;

  final SdkVersions sdk;
  final bool isFlutterProject;
  final String? name;
  final Pubspec? pubspec;
  final String? packageConfigPath;

  /// Which signal decided direct-vs-transitive, for `doctor`.
  final String dependencySource;

  final List<String> warnings;

  Directory get root => workspace.writeRoot;

  Directory get analysisRoot => workspace.analysisRoot;

  Iterable<PackageRef> get directPackages =>
      packages.values.where((pkg) => pkg.isDirect);

  PackageRef? package(String name) => packages[name];

  /// Whether the project depends on [name], optionally within [constraint]
  /// (any pub constraint string, e.g. `'^3.0.0'` or `'>=2.0.0 <3.0.0'`).
  bool hasPackage(String name, [String? constraint]) {
    final pkg = packages[name];
    if (pkg == null) return false;
    if (constraint == null) return true;
    final version = pkg.version;
    if (version == null) return false;
    try {
      return VersionConstraint.parse(constraint).allows(version);
    } on FormatException {
      return false;
    }
  }

  int? packageMajor(String name) => packages[name]?.version?.major;
}

/// Reads the target project. Never inspects the running script or
/// `Platform.version` -- under FVM or a global activation those describe a
/// different SDK than the one this project resolves against.
class ProjectResolver {
  const ProjectResolver({
    required this.fileSystem,
    required this.processRunner,
    this.allowProcessProbe = false,
  });

  final FileSystem fileSystem;
  final ProcessRunner processRunner;
  final bool allowProcessProbe;

  Project resolve(Directory start) {
    final warnings = <String>[];
    final workspace = WorkspaceResolver(fileSystem).resolve(start);

    final pubspec = _readPubspec(workspace.entryPackage, warnings);
    final packageConfig = _readPackageConfig(workspace, warnings);
    final lock = _readLock(workspace, warnings);
    final graph = _readPackageGraph(workspace, warnings);

    final packages = <String, PackageRef>{};
    var dependencySource = 'pubspec.yaml';

    // Versions and sources always come from the lockfile when there is one.
    lock.forEach((name, entry) => packages[name] = entry);

    // Direct-vs-transitive, in priority order.
    final graphKinds = graph;
    if (graphKinds != null && graphKinds.isNotEmpty) {
      dependencySource = '.dart_tool/package_graph.json';
      for (final entry in graphKinds.entries) {
        final existing = packages[entry.key];
        packages[entry.key] = (existing ??
                PackageRef(name: entry.key, kind: entry.value))
            .copyWith(kind: entry.value);
      }
      // Anything in the lock but absent from the graph root's lists is transitive.
      for (final name in packages.keys) {
        if (!graphKinds.containsKey(name)) {
          packages[name] = packages[name]!.copyWith(
            kind: DependencyKind.transitive,
          );
        }
      }
    } else if (lock.isNotEmpty) {
      dependencySource = 'pubspec.lock';
    }

    // pubspec.yaml is the floor: it also carries `sdk: flutter` deps, which
    // the lock records as `source: sdk, version: "0.0.0"`.
    if (pubspec != null) {
      _mergePubspecDeps(
        pubspec,
        packages,
        hasStrongerSignal: dependencySource != 'pubspec.yaml',
      );
    }

    // On-disk roots, needed for third-party `guidelines/` discovery.
    packageConfig.forEach((name, root) {
      final existing = packages[name];
      packages[name] =
          existing == null
              ? PackageRef(
                name: name,
                kind: DependencyKind.transitive,
                rootPath: root,
              )
              : existing.copyWith(rootPath: root);
    });

    final sdk = SdkResolver(
      fileSystem: fileSystem,
      processRunner: processRunner,
      allowProcessProbe: allowProcessProbe,
      onWarning: warnings.add,
    ).resolve(
      projectRoot: workspace.analysisRoot,
      flutterPackagePath: packageConfig['flutter'],
      packageConfigGeneratorVersion: _generatorVersion(workspace),
    );

    // `package_config.json` lists the root package itself; it is not one of
    // its own dependencies, and `usesMyApp` is not a useful flag.
    if (pubspec?.name != null) packages.remove(pubspec!.name);

    final isFlutter = _detectFlutter(workspace, packages, packageConfig);

    return Project(
      workspace: workspace,
      packages: packages,
      sdk: sdk,
      isFlutterProject: isFlutter,
      name: pubspec?.name,
      pubspec: pubspec,
      packageConfigPath: workspace.packageConfigFile?.path,
      dependencySource: dependencySource,
      warnings: warnings,
    );
  }

  // ---------------------------------------------------------------- pubspec

  Pubspec? _readPubspec(Directory dir, List<String> warnings) {
    final file = fileSystem.file(p.join(dir.path, 'pubspec.yaml'));
    if (!file.existsSync()) {
      // Everything downstream degrades quietly on a missing pubspec: the
      // composer still emits `foundation` and `dart`, and the writers still
      // create CLAUDE.md and .mcp.json. So running `dart run dart_boost@
      // install` from the wrong directory -- easy, since the remote-run form
      // needs no pubspec of its own -- scatters three files somewhere that is
      // not a package and reports success. Say so.
      warnings.add(
        'No pubspec.yaml in ${dir.path}. dart_boost keys its guidelines on a '
        'project\'s resolved dependencies, so it has almost nothing to go on '
        'here -- run it from a Dart or Flutter package root, or pass '
        '-C <path>.',
      );
      return null;
    }
    try {
      return Pubspec.parse(file.readAsStringSync(), lenient: true);
    } on Object catch (error) {
      warnings.add('Could not parse ${file.path}: $error');
      return null;
    }
  }

  void _mergePubspecDeps(
    Pubspec pubspec,
    Map<String, PackageRef> packages, {
    required bool hasStrongerSignal,
  }) {
    void apply(Map<String, Dependency> deps, DependencyKind kind) {
      for (final entry in deps.entries) {
        final existing = packages[entry.key];
        final source = _sourceOf(entry.value);
        final version = _versionOf(entry.value);
        if (existing == null) {
          packages[entry.key] = PackageRef(
            name: entry.key,
            kind: kind,
            version: version,
            source: source,
          );
        } else {
          packages[entry.key] = existing.copyWith(
            // The lock and graph are authoritative for kind when present.
            kind: hasStrongerSignal ? existing.kind : kind,
            source: existing.source ?? source,
            version: existing.version ?? version,
          );
        }
      }
    }

    apply(pubspec.dependencies, DependencyKind.directMain);
    apply(pubspec.devDependencies, DependencyKind.directDev);
    apply(pubspec.dependencyOverrides, DependencyKind.directOverridden);
  }

  static String _sourceOf(Dependency dependency) => switch (dependency) {
    SdkDependency() => 'sdk',
    PathDependency() => 'path',
    GitDependency() => 'git',
    _ => 'hosted',
  };

  static Version? _versionOf(Dependency dependency) {
    if (dependency is HostedDependency) {
      final constraint = dependency.version;
      // A caret/range constraint is not a resolution; only an exact pin is.
      if (constraint is Version) return constraint;
    }
    return null;
  }

  // ------------------------------------------------------------------- lock

  /// `pubspec.lock`'s `dependency:` field takes exactly four values, and
  /// `transitive` is unquoted while the others are quoted -- so this is parsed
  /// as YAML rather than matched against raw lines.
  Map<String, PackageRef> _readLock(
    WorkspaceInfo workspace,
    List<String> warnings,
  ) {
    for (final dir in <Directory>{
      workspace.analysisRoot,
      workspace.entryPackage,
    }) {
      final file = fileSystem.file(p.join(dir.path, 'pubspec.lock'));
      if (!file.existsSync()) continue;
      try {
        final doc = loadYaml(file.readAsStringSync());
        if (doc is! Map) continue;
        final packages = doc['packages'];
        if (packages is! Map) continue;
        final result = <String, PackageRef>{};
        packages.forEach((key, value) {
          if (key is! String || value is! Map) return;
          result[key] = PackageRef(
            name: key,
            kind: DependencyKind.fromLockValue('${value['dependency']}'),
            version: tryParseVersion(value['version']?.toString()),
            source: value['source']?.toString(),
          );
        });
        return result;
      } on Object catch (error) {
        warnings.add('Could not parse ${file.path}: $error');
      }
    }
    return <String, PackageRef>{};
  }

  // ------------------------------------------------------------------ graph

  /// The root entry of `.dart_tool/package_graph.json` (Dart >= 3.8) names its
  /// direct dependencies explicitly, which is strictly better than inferring
  /// them. Note the schema version field is `configVersion`, not `version`.
  Map<String, DependencyKind>? _readPackageGraph(
    WorkspaceInfo workspace,
    List<String> warnings,
  ) {
    final file = fileSystem.file(
      p.join(workspace.analysisRoot.path, '.dart_tool', 'package_graph.json'),
    );
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      final roots =
          (decoded['roots'] as List?)?.whereType<String>().toSet() ??
          <String>{};
      final entries =
          (decoded['packages'] as List?)?.whereType<Map<String, dynamic>>();
      if (entries == null) return null;

      final kinds = <String, DependencyKind>{};
      for (final entry in entries) {
        final name = entry['name'];
        if (name is! String || !roots.contains(name)) continue;
        for (final dep
            in (entry['dependencies'] as List?)?.whereType<String>() ??
                const <String>[]) {
          kinds[dep] = DependencyKind.directMain;
        }
        for (final dep
            in (entry['devDependencies'] as List?)?.whereType<String>() ??
                const <String>[]) {
          kinds.putIfAbsent(dep, () => DependencyKind.directDev);
        }
      }
      return kinds;
    } on Object catch (error) {
      warnings.add('Could not parse ${file.path}: $error');
      return null;
    }
  }

  // ---------------------------------------------------------- package config

  /// Package name -> resolved on-disk root.
  Map<String, String> _readPackageConfig(
    WorkspaceInfo workspace,
    List<String> warnings,
  ) {
    final file = workspace.packageConfigFile;
    if (file == null) return <String, String>{};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return <String, String>{};
      // `Uri.directory`, not `Uri.file`: pub writes a *relative* `rootUri`
      // for the root package, for every path dependency and for every
      // workspace member (hosted packages get an absolute one). Without the
      // trailing separator a directory URI carries, `.dart_tool` is treated
      // as the last *file* segment and `resolve('../vendor/x')` climbs one
      // level too many -- landing outside the project entirely, so path deps
      // get a `rootPath` that does not exist and their `guidelines/` tree is
      // never discovered.
      final base = Uri.directory(p.dirname(file.path));
      final result = <String, String>{};
      for (final entry
          in (decoded['packages'] as List?)
                  ?.whereType<Map<String, dynamic>>() ??
              const <Map<String, dynamic>>[]) {
        final name = entry['name'];
        final rootUri = entry['rootUri'];
        if (name is! String || rootUri is! String) continue;
        final resolved = base.resolve(rootUri);
        if (resolved.scheme != 'file') continue;
        result[name] = p.normalize(resolved.toFilePath());
      }
      return result;
    } on Object catch (error) {
      warnings.add('Could not parse ${file.path}: $error');
      return <String, String>{};
    }
  }

  String? _generatorVersion(WorkspaceInfo workspace) {
    final file = workspace.packageConfigFile;
    if (file == null) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic>
          ? decoded['generatorVersion'] as String?
          : null;
    } on Object {
      return null;
    }
  }

  bool _detectFlutter(
    WorkspaceInfo workspace,
    Map<String, PackageRef> packages,
    Map<String, String> packageConfig,
  ) {
    if (packages.containsKey('flutter') ||
        packageConfig.containsKey('flutter')) {
      return true;
    }
    final file = fileSystem.file(
      p.join(workspace.entryPackage.path, 'pubspec.yaml'),
    );
    if (!file.existsSync()) return false;
    try {
      final doc = loadYaml(file.readAsStringSync());
      return doc is Map && doc['flutter'] != null;
    } on Object {
      return false;
    }
  }
}
