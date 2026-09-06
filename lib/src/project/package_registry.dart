/// Package-name knowledge that the fragment tree depends on.
///
/// The Dart analog of Boost's `Support/PackageRegistry.php` plus the
/// `DiscoverPackagePaths` trait. Pub package names are already flat
/// identifiers, so the name mapping is identity for almost everything -- the
/// interesting parts are the priority and must-be-direct rules.
abstract final class PackageRegistry {
  /// Packages whose guidance lives elsewhere in the tree.
  ///
  /// `flutter` and friends are covered by the always-on `flutter/*`
  /// fragments, keyed on the *SDK* version rather than the pinned `0.0.0`
  /// the lockfile records for SDK-sourced packages.
  static const excluded = <String>{
    'dart_boost',
    'flutter',
    'flutter_test',
    'flutter_web_plugins',
    'flutter_localizations',
    'sky_engine',
  };

  /// When the key is present, every package in its value is dropped.
  ///
  /// The direct analog of Boost's `getPackagePriorities()` ("Pest beats
  /// PHPUnit"). A project on `hooks_riverpod` also has `flutter_riverpod` and
  /// `riverpod` in its graph; emitting all three produces three overlapping
  /// and occasionally contradictory sections.
  static const priorities = <String, Set<String>>{
    'hooks_riverpod': {'flutter_riverpod', 'riverpod'},
    'flutter_riverpod': {'riverpod'},
    'flutter_bloc': {'bloc'},
    'hydrated_bloc': {'bloc'},
    'flutter_lints': {'lints'},
    'very_good_analysis': {'flutter_lints', 'lints'},
    'mocktail': {'mockito'},
  };

  /// Guidance for these is only emitted when the project asked for them.
  ///
  /// Boost's `mustBeDirect`. Without it every project that transitively
  /// depends on `http` or `path` -- which is most of them -- gets guidance for
  /// a package the author never chose.
  static const mustBeDirect = <String>{
    'build_runner',
    'collection',
    'dio',
    'http',
    'intl',
    'json_annotation',
    'json_serializable',
    'logging',
    'meta',
    'mockito',
    'mocktail',
    'path',
    'shared_preferences',
    'test',
  };

  /// Fragment-directory name for a package.
  ///
  /// Identity for almost everything. The exceptions are binding packages that
  /// *re-export* a core package rather than competing with it: `flutter_bloc`
  /// is `bloc` plus widgets, and its major tracks `bloc`'s. Pointing the whole
  /// family at one directory is what makes [priorities] safe -- the rule picks
  /// which package supplies the version key, and the alias means the loser's
  /// guidance is not lost with it.
  static const _aliases = <String, String>{
    'flutter_riverpod': 'riverpod',
    'hooks_riverpod': 'riverpod',
    'flutter_bloc': 'bloc',
    'hydrated_bloc': 'bloc',
    'flutter_lints': 'lints',
  };

  static String guidelineName(String packageName) =>
      _aliases[packageName] ?? packageName;

  /// `flutter_riverpod` -> `FlutterRiverpod`, for renderer flag names.
  static String pascalCase(String packageName) =>
      packageName
          .split(RegExp(r'[_\-.]'))
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join();
}
