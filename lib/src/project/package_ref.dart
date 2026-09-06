import 'package:pub_semver/pub_semver.dart';

import '../util/version_key.dart';

/// How a package entered the resolution.
///
/// `pubspec.lock`'s `dependency:` field carries exactly these four values.
/// Note that `transitive` is emitted unquoted while the others are quoted --
/// parse the lockfile as YAML rather than string-matching raw lines.
enum DependencyKind {
  directMain('direct main'),
  directDev('direct dev'),
  directOverridden('direct overridden'),
  transitive('transitive');

  const DependencyKind(this.lockValue);

  final String lockValue;

  static DependencyKind fromLockValue(String value) {
    for (final kind in DependencyKind.values) {
      if (kind.lockValue == value) return kind;
    }
    return DependencyKind.transitive;
  }

  /// An overridden dependency is still one the user chose, so it counts.
  bool get isDirect => this != DependencyKind.transitive;
}

/// One resolved dependency of the target project.
class PackageRef {
  const PackageRef({
    required this.name,
    required this.kind,
    this.version,
    this.source,
    this.rootPath,
  });

  final String name;
  final DependencyKind kind;

  /// `null` for SDK-sourced packages (`flutter`, `flutter_test`), which the
  /// lockfile records as `version: "0.0.0"`, and for path/git deps without
  /// a resolved version.
  final Version? version;

  /// `hosted`, `path`, `git`, `sdk`.
  final String? source;

  /// On-disk package root from `package_config.json`, when available.
  final String? rootPath;

  bool get isDirect => kind.isDirect;

  bool get isDev => kind == DependencyKind.directDev;

  bool get isSdkPackage => source == 'sdk';

  /// The fragment-directory key, or `null` when there is no usable version.
  String? get versionKey {
    final v = version;
    if (v == null) return null;
    // SDK packages are pinned at 0.0.0 in the lockfile; a "0.0" key is noise.
    if (isSdkPackage && v == Version.none) return null;
    return versionKeyFor(v);
  }

  PackageRef copyWith({
    DependencyKind? kind,
    Version? version,
    String? source,
    String? rootPath,
  }) => PackageRef(
    name: name,
    kind: kind ?? this.kind,
    version: version ?? this.version,
    source: source ?? this.source,
    rootPath: rootPath ?? this.rootPath,
  );

  @override
  String toString() => '$name ${version ?? '-'} (${kind.lockValue})';
}

/// Indirection so [PackageRef] does not shadow the top-level function name.
String versionKeyFor(Version version) => versionKey(version);
