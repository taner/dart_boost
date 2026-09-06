import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// How the target directory sits inside its repository.
enum WorkspaceKind {
  /// A pub workspace (`workspace:` in the root pubspec). Members share one
  /// `.dart_tool/package_config.json` at the root.
  pubWorkspace('pub workspace'),

  /// A Melos monorepo. Members keep their own `.dart_tool/`, but agent config
  /// belongs at the repository root.
  melos('melos'),

  /// An ordinary single package.
  single('single package'),

  /// No `pubspec.yaml` anywhere above the target directory.
  implicit('no pubspec found');

  const WorkspaceKind(this.label);

  final String label;
}

/// Where to read from and where to write to.
///
/// These are not the same directory in a monorepo, and conflating them is how
/// you end up with nine copies of `AGENTS.md`.
class WorkspaceInfo {
  const WorkspaceInfo({
    required this.kind,
    required this.entryPackage,
    required this.analysisRoot,
    required this.writeRoot,
    this.packageConfigFile,
    this.members = const <String>[],
  });

  final WorkspaceKind kind;

  /// Nearest ancestor holding a `pubspec.yaml`.
  final Directory entryPackage;

  /// Directory owning the `.dart_tool/package_config.json` and `pubspec.lock`
  /// that describe [entryPackage]'s resolution.
  final Directory analysisRoot;

  /// Where `CLAUDE.md`, `.mcp.json` and `dart_boost.json` go.
  final Directory writeRoot;

  final File? packageConfigFile;

  /// Raw member patterns, for `doctor`.
  final List<String> members;

  bool get isMonorepo =>
      kind == WorkspaceKind.pubWorkspace || kind == WorkspaceKind.melos;
}

/// Mirrors `package:skills`' `WorkspaceResolver`: pub workspace, Melos, single
/// package, implicit -- in that order of specificity.
class WorkspaceResolver {
  const WorkspaceResolver(this.fileSystem);

  final FileSystem fileSystem;

  WorkspaceInfo resolve(Directory start) {
    final entry = _nearestWith(start, (dir) => _pubspecIn(dir) != null);
    if (entry == null) {
      return WorkspaceInfo(
        kind: WorkspaceKind.implicit,
        entryPackage: start,
        analysisRoot: start,
        writeRoot: start,
      );
    }

    final analysisRoot =
        _nearestWith(
          entry,
          (dir) =>
              fileSystem
                  .file(p.join(dir.path, '.dart_tool', 'package_config.json'))
                  .existsSync(),
        ) ??
        entry;

    final packageConfig = fileSystem.file(
      p.join(analysisRoot.path, '.dart_tool', 'package_config.json'),
    );

    // A pub workspace: some ancestor's pubspec lists `workspace:` members.
    final workspaceRoot = _nearestWith(entry, (dir) {
      final map = _readPubspecMap(dir);
      return map != null && map['workspace'] is List;
    });
    if (workspaceRoot != null) {
      final map = _readPubspecMap(workspaceRoot)!;
      return WorkspaceInfo(
        kind: WorkspaceKind.pubWorkspace,
        entryPackage: entry,
        analysisRoot: analysisRoot,
        writeRoot: workspaceRoot,
        packageConfigFile: packageConfig.existsSync() ? packageConfig : null,
        members: _stringList(map['workspace']),
      );
    }

    // Melos: `melos.yaml`, or a `melos:` block in the root pubspec (Melos 6+).
    final melosRoot = _nearestWith(entry, (dir) {
      if (fileSystem.file(p.join(dir.path, 'melos.yaml')).existsSync()) {
        return true;
      }
      final map = _readPubspecMap(dir);
      return map != null && map['melos'] != null;
    });
    if (melosRoot != null) {
      return WorkspaceInfo(
        kind: WorkspaceKind.melos,
        entryPackage: entry,
        analysisRoot: analysisRoot,
        writeRoot: melosRoot,
        packageConfigFile: packageConfig.existsSync() ? packageConfig : null,
        members: _melosPackages(melosRoot),
      );
    }

    return WorkspaceInfo(
      kind: WorkspaceKind.single,
      entryPackage: entry,
      analysisRoot: analysisRoot,
      writeRoot: entry,
      packageConfigFile: packageConfig.existsSync() ? packageConfig : null,
    );
  }

  Directory? _nearestWith(Directory start, bool Function(Directory) test) {
    var dir = fileSystem.directory(p.canonicalize(start.path));
    while (true) {
      if (test(dir)) return dir;
      final parent = dir.parent;
      if (p.equals(parent.path, dir.path)) return null;
      dir = parent;
    }
  }

  File? _pubspecIn(Directory dir) {
    final file = fileSystem.file(p.join(dir.path, 'pubspec.yaml'));
    return file.existsSync() ? file : null;
  }

  Map<Object?, Object?>? _readPubspecMap(Directory dir) {
    final file = _pubspecIn(dir);
    if (file == null) return null;
    try {
      final doc = loadYaml(file.readAsStringSync());
      return doc is Map ? doc : null;
    } on Object {
      return null;
    }
  }

  List<String> _melosPackages(Directory root) {
    final melosFile = fileSystem.file(p.join(root.path, 'melos.yaml'));
    Object? packages;
    if (melosFile.existsSync()) {
      try {
        final doc = loadYaml(melosFile.readAsStringSync());
        if (doc is Map) packages = doc['packages'];
      } on Object {
        packages = null;
      }
    }
    if (packages == null) {
      final map = _readPubspecMap(root);
      final melos = map?['melos'];
      if (melos is Map) packages = melos['packages'];
      packages ??= map?['workspace'];
    }
    return _stringList(packages);
  }

  static List<String> _stringList(Object? value) =>
      value is List
          ? value.whereType<Object>().map((e) => e.toString()).toList()
          : const <String>[];
}
