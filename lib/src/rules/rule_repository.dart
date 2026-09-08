import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../writers/atomic_writer.dart';
import 'rule_area.dart';
import 'rule_file.dart';

class RuleWriteResult {
  const RuleWriteResult({required this.path, required this.created});

  final String path;
  final bool created;
}

/// Reads and writes `.ai/rules/`.
///
/// Knows nothing about MCP. The server is a thin adapter over this, so an
/// upstream break in `package:dart_mcp` cannot reach the rules themselves.
class RuleRepository {
  RuleRepository({
    required this.fileSystem,
    required this.projectRoot,
    this.dryRun = false,
  })
    // normalizeGlob does a literal string-prefix comparison against this
    // value, so a trailing separator or an un-resolved `..` would silently
    // break every glob comparison. Normalize once, here, and use this value
    // everywhere below instead of `projectRoot.path`.
    : _rootPath = p.normalize(projectRoot.path);

  final FileSystem fileSystem;
  final Directory projectRoot;
  final bool dryRun;
  final String _rootPath;

  static const relativeDirectory = '.ai/rules';
  static const indexFileName = 'index.md';

  String get directory =>
      p.join(_rootPath, p.joinAll(relativeDirectory.split('/')));

  String get indexPath => p.join(directory, indexFileName);

  RuleWriteResult write({
    required String glob,
    required String title,
    required String note,
  }) {
    final normalized = normalizeGlob(glob, projectRoot: _rootPath);
    if (normalized == null) {
      throw ArgumentError.value(glob, 'glob', 'outside the project root');
    }

    final cleanTitle = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final cleanNote = note.trim();

    final existing = readAll();
    final target = _resolveTarget(normalized, existing);

    final String content;
    if (target.file == null) {
      content = renderRuleFile(
        paths: <String>[normalized],
        heading: _headingFor(target.path),
        body: '## $cleanTitle\n\n$cleanNote',
      );
    } else {
      final current = target.file!;
      final paths = <String>[
        ...current.paths,
        if (!current.paths.contains(normalized)) normalized,
      ];
      final rendered = renderRuleFile(
        paths: paths,
        heading: current.heading,
        body:
            '${current.bodyWithoutHeading}\n\n## $cleanTitle\n\n$cleanNote'
                .trim(),
      );
      // Restore the file's own line endings, the same deal the JSON and TOML
      // splicers make: appending in LF to a CRLF file would rewrite every
      // line, the whole-file git noise the deterministic index sorting
      // exists to prevent.
      content = current.crlf ? rendered.replaceAll('\n', '\r\n') : rendered;
    }

    _write(target.path, content);
    writeIndex();

    return RuleWriteResult(path: target.path, created: target.file == null);
  }

  List<RuleFile> readAll({void Function(String)? onWarning}) {
    final dir = fileSystem.directory(directory);
    if (!dir.existsSync()) return <RuleFile>[];

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path) == '.md')
            .where((f) => p.basename(f.path) != indexFileName)
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final parsed = <RuleFile>[];
    for (final file in files) {
      final rule = RuleFile.parse(file.path, file.readAsStringSync());
      if (rule == null) {
        onWarning?.call(
          'Skipping ${p.basename(file.path)}: no valid `paths` frontmatter. '
          'The file was left untouched.',
        );
        continue;
      }
      parsed.add(rule);
    }
    return parsed;
  }

  /// Rebuilds `index.md` from whatever is on disk. Returns whether it changed.
  bool writeIndex({void Function(String)? onWarning}) {
    final rules = readAll(onWarning: onWarning);

    final rows = <({String glob, String file})>[
        for (final rule in rules)
          for (final glob in rule.paths)
            (glob: glob, file: _relative(rule.path)),
      ]
      // The index is committed to git. Sorting by file then glob makes
      // its contents a pure function of what's on disk, independent of
      // write order or directory-listing order -- otherwise every
      // regeneration would be permanent, unreviewable git noise.
      ..sort((a, b) {
        final byFile = a.file.compareTo(b.file);
        return byFile != 0 ? byFile : a.glob.compareTo(b.glob);
      });

    final buffer =
        StringBuffer()
          ..writeln('# Project Rules Index')
          ..writeln()
          ..writeln(
            'Before planning or editing a file, find the row whose globs match its '
            'path and read that rule file.',
          )
          ..writeln()
          ..writeln('| Applies to | Rule file |')
          ..writeln('| --- | --- |');

    for (final row in rows) {
      buffer.writeln('| `${row.glob}` | `${row.file}` |');
    }

    return _write(indexPath, buffer.toString());
  }

  ({String path, RuleFile? file}) _resolveTarget(
    String glob,
    List<RuleFile> existing,
  ) {
    final area = areaKey(glob);

    for (final rule in existing) {
      // `p` is the package:path alias used throughout this file, and
      // `existing` is already this method's parameter name; call the glob
      // being compared `otherGlob` so neither is shadowed.
      final matches =
          rule.paths.contains(glob) ||
          rule.paths.any((otherGlob) => areaKey(otherGlob) == area);
      if (matches) return (path: rule.path, file: rule);
    }

    final taken = existing.map((r) => p.basename(r.path)).toSet();
    for (final candidate in filenameCandidates(glob)) {
      final name = '$candidate.md';
      if (name == indexFileName || taken.contains(name)) continue;
      if (fileSystem.file(p.join(directory, name)).existsSync()) continue;
      return (path: p.join(directory, name), file: null);
    }

    final base = filenameCandidates(glob).last;
    var suffix = 2;
    while (true) {
      final name = '$base-$suffix.md';
      if (!taken.contains(name) &&
          !fileSystem.file(p.join(directory, name)).existsSync()) {
        return (path: p.join(directory, name), file: null);
      }
      suffix++;
    }
  }

  bool _write(String path, String content) {
    fileSystem.directory(p.dirname(path)).createSync(recursive: true);
    // Rule files are created and owned by dart_boost, and are git-tracked
    // themselves -- a `.dart-boost.bak` beside every one would just be
    // committed noise, unlike the user-owned config files AtomicWriter
    // otherwise backs up.
    return AtomicWriter(
      fileSystem,
      dryRun: dryRun,
    ).write(path, content, backup: false);
  }

  String _relative(String path) =>
      p.relative(path, from: _rootPath).replaceAll(r'\', '/');

  static String _headingFor(String path) {
    final base = p.basenameWithoutExtension(path);
    return base
        .split('-')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
