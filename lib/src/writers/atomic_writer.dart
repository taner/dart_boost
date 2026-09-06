import 'package:file/file.dart';

/// Write-or-don't for user-owned config files.
///
/// Two properties matter: the file is never left half-written (temp file plus
/// rename), and the original is recoverable (a one-time `.dart-boost.bak`
/// dropped before the first modification).
class AtomicWriter {
  const AtomicWriter(this.fileSystem, {this.dryRun = false});

  final FileSystem fileSystem;
  final bool dryRun;

  static const backupSuffix = '.dart-boost.bak';
  static const _tempSuffix = '.dart-boost.tmp';

  /// Returns `true` when the file's contents would change.
  bool write(String path, String content, {bool backup = true}) {
    final file = fileSystem.file(path);
    final exists = file.existsSync();

    if (exists && file.readAsStringSync() == content) return false;
    if (dryRun) return true;

    file.parent.createSync(recursive: true);

    if (backup && exists) {
      final backupFile = fileSystem.file('$path$backupSuffix');
      if (!backupFile.existsSync()) file.copySync(backupFile.path);
    }

    final temp = fileSystem.file('$path$_tempSuffix')
      ..writeAsStringSync(content);
    temp.renameSync(path);
    return true;
  }
}
