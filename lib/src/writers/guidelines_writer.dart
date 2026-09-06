import 'dart:convert';

import 'package:file/file.dart';

enum GuidelineWriteOutcome {
  created('written'),
  replaced('updated'),
  unchanged('already up to date'),
  empty('nothing to write');

  const GuidelineWriteOutcome(this.label);

  final String label;
}

/// Writes the composed guidelines into an agent's Markdown file, leaving
/// everything the user wrote around it alone.
///
/// A straight port of Boost's `GuidelineWriter`, including the detail that is
/// easy to get wrong: the sentinel block is replaced **first-match only**, so
/// content the user added *after* our block keeps its position instead of
/// being shunted to the end on every run.
class GuidelinesWriter {
  const GuidelinesWriter(this.fileSystem, {this.dryRun = false});

  final FileSystem fileSystem;
  final bool dryRun;

  static const openTag = '<dart-boost-guidelines>';
  static const closeTag = '</dart-boost-guidelines>';

  static final _block = RegExp('$openTag.*?$closeTag', dotAll: true);
  static final _blankRuns = RegExp(r'\n{3,}');

  GuidelineWriteOutcome write({
    required String path,
    required String guidelines,
    bool frontmatter = false,
  }) {
    if (guidelines.trim().isEmpty) return GuidelineWriteOutcome.empty;

    final file = fileSystem.file(path);

    if (dryRun) {
      // Must not open the file: `FileMode.append` would create it, and a dry
      // run that leaves an empty CLAUDE.md behind is worse than no dry run.
      final existing = file.existsSync() ? file.readAsStringSync() : '';
      final result = _compose(existing, guidelines, frontmatter: frontmatter);
      return result.outcome;
    }

    file.parent.createSync(recursive: true);

    // `append` is Dart's `c+`: read/write, creates, does not truncate. It is
    // the only mode that lets us lock before reading.
    final handle = file.openSync(mode: FileMode.append);
    try {
      _tryLock(handle);
      handle.setPositionSync(0);
      final existing = utf8.decode(handle.readSync(handle.lengthSync()));

      final result = _compose(existing, guidelines, frontmatter: frontmatter);
      if (result.outcome == GuidelineWriteOutcome.unchanged) {
        return result.outcome;
      }

      handle
        ..truncateSync(0)
        ..setPositionSync(0)
        ..writeStringSync(result.content);

      return result.outcome;
    } finally {
      _tryUnlock(handle);
      handle.closeSync();
    }
  }

  static _Composed _compose(
    String existing,
    String guidelines, {
    required bool frontmatter,
  }) {
    final replacement = '$openTag\n${guidelines.trim()}\n\n$closeTag';
    final replaced = _block.hasMatch(existing);

    final updated =
        replaced
            ? existing.replaceFirst(_block, replacement)
            : _append(existing, replacement, frontmatter: frontmatter);

    final normalized = _normalize(updated);
    if (normalized == existing) {
      return _Composed(normalized, GuidelineWriteOutcome.unchanged);
    }
    return _Composed(
      normalized,
      replaced ? GuidelineWriteOutcome.replaced : GuidelineWriteOutcome.created,
    );
  }

  static String _append(
    String existing,
    String replacement, {
    required bool frontmatter,
  }) {
    final prefix =
        frontmatter && !existing.contains('\n---\n')
            ? '---\nalwaysApply: true\n---\n'
            : '';
    final trimmed = existing.trimRight();
    final separator = trimmed.isEmpty ? '' : '\n\n===\n\n';
    return '$prefix$trimmed$separator$replacement';
  }

  static String _normalize(String content) {
    final collapsed = content.replaceAll(_blankRuns, '\n\n');
    return collapsed.endsWith('\n') ? collapsed : '$collapsed\n';
  }

  /// Advisory on POSIX and unimplemented on `MemoryFileSystem`, so failure is
  /// not fatal -- for a one-shot CLI the lock is belt-and-braces anyway.
  void _tryLock(RandomAccessFile handle) {
    try {
      handle.lockSync(FileLock.exclusive);
    } on Object {
      // Best effort.
    }
  }

  void _tryUnlock(RandomAccessFile handle) {
    try {
      handle.unlockSync();
    } on Object {
      // Best effort.
    }
  }
}

class _Composed {
  const _Composed(this.content, this.outcome);

  final String content;
  final GuidelineWriteOutcome outcome;
}
