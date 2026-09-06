import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:package_config/package_config.dart' as pc;
import 'package:path/path.dart' as p;

/// Locates the `guidelines/` tree that ships inside this package.
///
/// The tree is deliberately **not** dot-prefixed: `dart pub publish` strips
/// every dot-prefixed file and directory, so a `.ai/` tree would work locally
/// and be entirely absent from the pub.dev release.
///
/// Finding *our own* assets and finding the *target project's* dependencies
/// are two different questions with two different answers. This class only
/// answers the first; see `ProjectResolver` for the second.
class BundledAssets {
  const BundledAssets(this.root, this.guidelines);

  /// The package root -- the directory holding `pubspec.yaml` and `lib/`.
  final Directory root;

  /// `<root>/guidelines`.
  final Directory guidelines;

  static const _anchor = 'package:dart_boost/dart_boost.dart';

  /// Resolves the bundled tree, or returns `null` when it cannot be found.
  ///
  /// Tries [Isolate.resolvePackageUriSync] first: it works when dart_boost is
  /// a dev_dependency, globally activated, *or* invoked through
  /// `dart run dart_boost@`, where we are not in the target project's
  /// `package_config.json` at all. It returns `null` under AOT
  /// (`dart compile exe`), hence the `findPackageConfig` fallback.
  static Future<BundledAssets?> locate({
    FileSystem fileSystem = const LocalFileSystem(),
    Uri? scriptUri,
  }) async {
    final direct = _fromLibUri(_resolveAnchorSync(), fileSystem);
    if (direct != null) return direct;

    return _fromPackageConfig(fileSystem, scriptUri);
  }

  static Uri? _resolveAnchorSync() {
    try {
      return Isolate.resolvePackageUriSync(Uri.parse(_anchor));
    } on Object {
      // `UnsupportedError` under AOT, `ArgumentError` for a malformed anchor.
      return null;
    }
  }

  static Future<BundledAssets?> _fromPackageConfig(
    FileSystem fileSystem,
    Uri? scriptUri,
  ) async {
    for (final start in _searchRoots(scriptUri)) {
      try {
        final config = await pc.findPackageConfig(start);
        final package = config?['dart_boost'];
        if (package == null) continue;
        final resolved = _fromRootUri(package.root, fileSystem);
        if (resolved != null) return resolved;
      } on Object {
        continue;
      }
    }
    return null;
  }

  static Iterable<io.Directory> _searchRoots(Uri? scriptUri) sync* {
    final script = scriptUri ?? _platformScript();
    if (script != null && script.scheme == 'file') {
      yield io.Directory(p.dirname(script.toFilePath()));
    }
    yield io.Directory(p.current);
  }

  static Uri? _platformScript() {
    try {
      final script = io.Platform.script;
      return script.scheme == 'file' ? script : null;
    } on Object {
      return null;
    }
  }

  /// `file:///…/dart_boost/lib/dart_boost.dart` -> package root two levels up.
  static BundledAssets? _fromLibUri(Uri? libFileUri, FileSystem fileSystem) {
    if (libFileUri == null || libFileUri.scheme != 'file') return null;
    final root = p.dirname(p.dirname(libFileUri.toFilePath()));
    return _at(root, fileSystem);
  }

  static BundledAssets? _fromRootUri(Uri rootUri, FileSystem fileSystem) {
    if (rootUri.scheme != 'file') return null;
    return _at(rootUri.toFilePath(), fileSystem);
  }

  static BundledAssets? _at(String root, FileSystem fileSystem) {
    final guidelines = fileSystem.directory(p.join(root, 'guidelines'));
    if (!guidelines.existsSync()) return null;
    return BundledAssets(fileSystem.directory(root), guidelines);
  }

  /// The bundled fragment for [key] (`flutter/core`, `riverpod/3/core`), or
  /// `null` when no such fragment ships.
  File? fragment(String key) {
    final file = guidelines.fileSystem.file(
      '${p.joinAll([guidelines.path, ...key.split('/')])}.md',
    );
    return file.existsSync() ? file : null;
  }

  /// Every `.md` directly inside `guidelines/<dir>`, sorted by name.
  List<File> fragmentsIn(String dir) {
    final directory = guidelines.fileSystem.directory(
      p.joinAll([guidelines.path, ...dir.split('/')]),
    );
    if (!directory.existsSync()) return const <File>[];
    return directory
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.md')
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }
}
