import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../assets/bundled_assets.dart';
import '../project/package_ref.dart';
import '../project/package_registry.dart';
import '../project/project.dart';
import 'facts.dart';
import 'markdown_formatter.dart';
import 'renderer.dart';

/// One fragment that made it into the composed output.
class ComposedFragment {
  const ComposedFragment({
    required this.key,
    required this.content,
    this.path,
    this.custom = false,
    this.thirdParty = false,
  });

  /// The `=== <key> rules ===` heading, and the override path under
  /// `.ai/guidelines/`.
  final String key;

  final String content;
  final String? path;

  /// Came from the project's own `.ai/guidelines/` tree.
  final bool custom;

  /// Came from a dependency's `guidelines/` tree.
  final bool thirdParty;
}

class ComposeResult {
  const ComposeResult({
    required this.content,
    required this.fragments,
    this.warnings = const <String>[],
    this.untrustedThirdParty = const <String>[],
  });

  final String content;
  final List<ComposedFragment> fragments;
  final List<String> warnings;

  /// Direct dependencies that ship a `guidelines/` tree but are not on the
  /// trust allowlist, so nothing was read from them.
  final List<String> untrustedThirdParty;

  bool get isEmpty => content.trim().isEmpty;

  List<String> get keys => fragments.map((f) => f.key).toList();
}

/// Resolves and layers fragments into one project-tailored Markdown blob.
///
/// Following Boost, there is **no range matching and no fallback to a
/// nearest-lower version**: a missing version directory contributes nothing.
/// That is a deliberate simplicity/predictability trade-off -- a fragment
/// either matches your resolved major or it does not apply.
class GuidelineComposer {
  GuidelineComposer({
    required this.fileSystem,
    required this.assets,
    required this.project,
    required this.facts,
    this.trustedThirdParty = const <String>[],
    this.excludeKeys = const <String>{},
    this.renderer = const GuidelineRenderer(),
    this.userGuidelineDir = '.ai/guidelines',
  });

  final FileSystem fileSystem;
  final BundledAssets assets;
  final Project project;
  final GuidelineFacts facts;
  final List<String> trustedThirdParty;
  final Set<String> excludeKeys;
  final GuidelineRenderer renderer;

  /// Where a project overrides or extends the bundled tree. Dot-prefixed is
  /// fine here: this lives in the *user's* repository, not in a published
  /// package, so `dart pub publish`'s dotfile stripping does not apply.
  final String userGuidelineDir;

  ComposeResult compose() {
    final warnings = <String>[];
    final untrusted = <String>[];

    // Source path per key, in composition order.
    final sources = <String, File>{};

    void add(String key, File? file) {
      if (file == null || excludeKeys.contains(key)) return;
      sources[key] = file;
    }

    // --- core (always) ---
    add('foundation', assets.fragment('foundation'));
    add('dart', assets.fragment('dart/core'));

    // --- conditional ---
    if (project.isFlutterProject) {
      add('flutter', assets.fragment('flutter/core'));
      final sdkKey = project.sdk.flutterKey;
      if (sdkKey != null) {
        add('flutter/v$sdkKey', assets.fragment('flutter/$sdkKey/core'));
      }
    }
    if (facts.hasFlag('usesFvm')) add('fvm', assets.fragment('fvm/core'));
    if (facts.hasFlag('isMelosWorkspace')) {
      add('melos', assets.fragment('melos/core'));
    }
    if (facts.hasFlag('hasTests')) {
      add('testing', assets.fragment('testing/core'));
    }

    // --- detected packages ---
    for (final package in _eligiblePackages()) {
      final dir = PackageRegistry.guidelineName(package.name);
      add('$dir/core', assets.fragment('$dir/core'));

      final key = package.versionKey;
      if (key == null) continue;
      add('$dir/v$key', assets.fragment('$dir/$key/core'));
      for (final file in assets.fragmentsIn('$dir/$key')) {
        final name = p.basenameWithoutExtension(file.path);
        if (name == 'core') continue;
        add('$dir/v$key/$name', file);
      }
    }

    // --- third party ---
    final thirdParty = _thirdPartyFragments(warnings, untrusted);
    for (final entry in thirdParty.entries) {
      add(entry.key, entry.value);
    }

    // --- user overrides ---
    // An override replaces the bundled fragment *in place*, so the reading
    // order the fragment tree establishes is preserved. User files that match
    // no bundled fragment are new content and go first.
    //
    // The override path mirrors the *bundled tree*, not the output key:
    // `.ai/guidelines/riverpod/3/core.md` overrides the fragment that appears
    // as `riverpod/v3`. Mirroring the tree is what makes an override
    // discoverable -- you copy the file you want to change.
    final overridden = <String>{};
    for (final entry in sources.entries.toList()) {
      final override = _userFile(_overrideKeyFor(entry.key, entry.value));
      if (override == null) continue;
      sources[entry.key] = override;
      overridden.add(p.canonicalize(override.path));
    }

    final custom = <String, File>{};
    for (final file in _userFiles()) {
      if (overridden.contains(p.canonicalize(file.path))) continue;
      final key = '.ai/${_relativeKey(_userDir().path, file.path)}';
      if (excludeKeys.contains(key)) continue;
      custom[key] = file;
    }

    final ordered = <String, File>{...custom, ...sources};

    // --- render ---
    final fragments = <ComposedFragment>[];
    for (final entry in ordered.entries) {
      final rendered = _render(entry.key, entry.value, warnings);
      if (rendered == null || rendered.trim().isEmpty) continue;
      final path = p.canonicalize(entry.value.path);
      fragments.add(
        ComposedFragment(
          key: entry.key,
          content: rendered.trim(),
          path: entry.value.path,
          custom: custom.containsKey(entry.key) || overridden.contains(path),
          thirdParty: thirdParty.containsKey(entry.key),
        ),
      );
    }

    return ComposeResult(
      content: assemble(fragments),
      fragments: fragments,
      warnings: warnings,
      untrustedThirdParty: untrusted,
    );
  }

  /// `=== <key> rules ===` separators so a human reading the generated file
  /// can see which fragment produced which guidance.
  static String assemble(List<ComposedFragment> fragments) {
    if (fragments.isEmpty) return '';
    final buffer = StringBuffer();
    for (final fragment in fragments) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer
        ..writeln('=== ${fragment.key} rules ===')
        ..writeln()
        ..writeln(fragment.content);
    }
    return MarkdownFormatter.format(buffer.toString());
  }

  // ------------------------------------------------------------- selection

  /// Boost's `shouldExcludePackage`, ported.
  Iterable<PackageRef> _eligiblePackages() {
    final names = project.packages.keys.toSet();
    final sorted =
        project.packages.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return sorted.where((package) {
      if (PackageRegistry.excluded.contains(package.name)) return false;

      for (final entry in PackageRegistry.priorities.entries) {
        if (entry.value.contains(package.name) && names.contains(entry.key)) {
          return false;
        }
      }

      if (!package.isDirect &&
          PackageRegistry.mustBeDirect.contains(package.name)) {
        return false;
      }
      return true;
    });
  }

  // ----------------------------------------------------------- third party

  /// A dependency contributes by shipping `guidelines/**/*.md` at its package
  /// root -- deliberately the sibling of the `skills/` directory
  /// `package:skills` already established.
  ///
  /// Direct dependencies only, same as skills: scanning transitives pulls in
  /// guidance for packages the user never chose. And nothing is read without
  /// explicit per-package opt-in, because this is text from an arbitrary pub
  /// package headed for an agent's system prompt.
  Map<String, File> _thirdPartyFragments(
    List<String> warnings,
    List<String> untrusted,
  ) {
    final result = <String, File>{};

    for (final package in project.directPackages) {
      final root = package.rootPath;
      if (root == null || PackageRegistry.excluded.contains(package.name)) {
        continue;
      }

      final dir = fileSystem.directory(p.join(root, 'guidelines'));
      if (!dir.existsSync()) continue;

      if (!trustedThirdParty.contains(package.name)) {
        untrusted.add(package.name);
        continue;
      }

      if (!_manifestAccepts(dir, package.name, warnings)) continue;

      final files =
          dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => p.extension(f.path) == '.md')
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        result['${package.name}/${_relativeKey(dir.path, file.path)}'] = file;
      }
    }

    return result;
  }

  /// A fragment written against a newer facts contract than we implement will
  /// branch on flags we do not define. Skipping it with a warning beats
  /// emitting subtly wrong guidance.
  bool _manifestAccepts(
    Directory dir,
    String packageName,
    List<String> warnings,
  ) {
    final manifest = fileSystem.file(p.join(dir.path, 'manifest.yaml'));
    if (!manifest.existsSync()) return true;
    try {
      final doc = loadYaml(manifest.readAsStringSync());
      if (doc is! Map) return true;
      final declared = doc['boost_facts_version'];
      if (declared is! int) return true;
      if (declared > GuidelineFacts.factsVersion) {
        warnings.add(
          'Skipping $packageName guidelines: they declare facts version '
          '$declared, this dart_boost implements ${GuidelineFacts.factsVersion}.',
        );
        return false;
      }
      return true;
    } on Object catch (error) {
      warnings.add(
        'Skipping $packageName guidelines: unreadable manifest ($error)',
      );
      return false;
    }
  }

  // ------------------------------------------------------------- user tree

  /// Where a user override for this entry would live, relative to
  /// `.ai/guidelines/`. Bundled fragments mirror their path in the bundled
  /// tree; anything else (third-party, user-only) is addressed by its key.
  String _overrideKeyFor(String key, File file) {
    final bundled = p.canonicalize(assets.guidelines.path);
    final path = p.canonicalize(file.path);
    if (!p.isWithin(bundled, path)) return key;
    return _relativeKey(bundled, path);
  }

  Directory _userDir() => fileSystem.directory(
    p.joinAll(<String>[project.root.path, ...userGuidelineDir.split('/')]),
  );

  File? _userFile(String key) {
    final file = fileSystem.file(
      '${p.joinAll([_userDir().path, ...key.split('/')])}.md',
    );
    return file.existsSync() ? file : null;
  }

  List<File> _userFiles() {
    final dir = _userDir();
    if (!dir.existsSync()) return const <File>[];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.md')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  static String _relativeKey(String root, String filePath) => p
      .withoutExtension(p.relative(filePath, from: root))
      .replaceAll(r'\', '/');

  // -------------------------------------------------------------- rendering

  /// Returns `null` when the fragment could not be read at all. Render
  /// problems degrade to warnings: a bad fragment omits itself, it never
  /// aborts the install.
  String? _render(String key, File file, List<String> warnings) {
    String source;
    try {
      source = file.readAsStringSync();
    } on FileSystemException catch (error) {
      warnings.add('Could not read fragment $key: ${error.message}');
      return null;
    }

    final result = renderer.render(
      source,
      flags: facts.flags,
      variables: facts.variables,
      isKnownFlag: facts.isKnownFlag,
    );

    for (final flag in result.unknownFlags) {
      warnings.add(
        'Fragment $key branches on unknown flag `$flag` (treated as false)',
      );
    }
    for (final variable in result.unknownVars) {
      warnings.add(
        'Fragment $key references unknown variable `$variable` (left as-is)',
      );
    }
    for (final error in result.errors) {
      warnings.add('Fragment $key: $error');
    }

    return result.content;
  }
}
